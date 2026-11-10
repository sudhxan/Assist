import AVFoundation
import Foundation

/// `Assist --bench-logic`: feeds scripted meetings through a real `AppModel` and checks what
/// it would ask the model at each point — which question it thinks is current, what it
/// remembers of earlier ones, and who it thinks said what. Nothing is sent anywhere.
@MainActor
enum LogicBench {
    private static var failures = 0

    static func run() async {
        print("\n== Conversation logic: question tracking, memory, speaker attribution")
        failures = 0
        await followUps()
        await echoes()
        await ordering()
        await longMeeting()
        await lengths()
        tracker()
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures += 1 }
        print("  \(ok ? "✓" : "✗") \(name)" + (ok ? "" : "\n      " + detail().replacingOccurrences(of: "\n", with: "\n      ")))
    }

    private final class Probe {
        var requests: [(title: String, request: LLMRequest)] = []
        var last: (title: String, request: LLMRequest)? { requests.last }
    }

    private static func makeModel(_ probe: Probe) -> AppModel {
        let suite = "com.sudhan.assist.bench"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(defaults: defaults)
        model.provider = .claude
        model.systemAudioActive = true
        model.activeSpeechEngine = .parakeet
        model.sessionStart = Date()
        model.requestProbe = { probe.requests.append(($0, $1)) }
        return model
    }

    private static func say(_ model: AppModel, _ speaker: Speaker, _ text: String, wait: Double = 0.5) async {
        model.audio.onTranscript?(speaker, .volatile(text))
        model.audio.onTranscript?(speaker, .final(text))
        try? await Task.sleep(for: .seconds(wait))
    }

    private static func state(_ request: LLMRequest?) -> String {
        guard let text = request?.text, let open = text.range(of: "<conversation_state>\n"),
              let close = text.range(of: "\n</conversation_state>") else { return "" }
        return String(text[open.upperBound..<close.lowerBound])
    }

    private static func task(_ request: LLMRequest?) -> String {
        guard let text = request?.text, let open = text.range(of: "<task>\n") else { return "" }
        return String(text[open.upperBound...])
    }

    // MARK: Scenarios

    private static func followUps() async {
        print("\nA new question, then a follow-up, then pressing Answer mid-reply")
        let probe = Probe()
        let model = makeModel(probe)

        await say(model, .them, "Thanks for joining. How does your team handle incident response today?")
        check("first question is answered automatically", probe.requests.count == 1 && probe.last?.title.contains("incident response") == true,
              "requests: \(probe.requests.map(\.title))")
        check("memory holds it as unanswered", state(probe.last?.request).contains("1. [0:00] They asked")
              && state(probe.last?.request).contains("I said: (nothing yet)") && state(probe.last?.request).contains("waiting on my answer to #1"),
              state(probe.last?.request))

        await say(model, .me, "We run a weekly on-call rotation with a primary and a secondary.", wait: 3)
        await say(model, .them, "And why did you pick that?")
        let followUp = probe.last
        check("the follow-up becomes the current question", probe.requests.count == 2 && followUp?.title == "And why did you pick that?",
              "requests: \(probe.requests.map(\.title))")
        check("memory carries the first question and what I answered",
              state(followUp?.request).contains("incident response") && state(followUp?.request).contains("I said: We run a weekly on-call rotation")
              && state(followUp?.request).contains("waiting on my answer to #2"), state(followUp?.request))
        check("the task tells the model to resolve it against that history", task(followUp?.request).contains("And why did you pick that?")
              && task(followUp?.request).contains("what I already said"), task(followUp?.request))

        await say(model, .me, "Mostly because it keeps context with one person for the week.", wait: 3)
        model.answerNow()
        check("Answer mid-reply continues my answer instead of re-answering", probe.requests.count == 3
              && task(probe.last?.request).contains("I've started answering") && task(probe.last?.request).contains("keeps context with one person")
              && probe.last?.title == "And why did you pick that?", task(probe.last?.request))

        await say(model, .them, "Mm-hm, okay.")
        model.answerNow()
        check("their \"mm-hm, okay\" doesn't steal the turn", task(probe.last?.request).contains("I've started answering"), task(probe.last?.request))

        await say(model, .me, "Yeah.", wait: 3)
        await say(model, .them, "Walk me through the worst outage you handled and what you changed afterwards.")
        let before = probe.requests.count
        await say(model, .me, "Okay.", wait: 0.2)
        model.answerNow()
        check("my \"okay\" isn't taken for an answer: Answer still targets their question", probe.requests.count == before + 1
              && probe.last?.title.contains("worst outage") == true && state(probe.last?.request).contains("waiting on my answer to #3"),
              "title: \(probe.last?.title ?? "-")\n" + state(probe.last?.request))
        model.stopListening()
    }

    private static func lengths() async {
        print("\nQuick / Explain / Elaborate on a question, and typed requests for detail")
        let probe = Probe()
        let model = makeModel(probe)
        await say(model, .them, "How would you design a rate limiter for our public API?")
        let auto = probe.last?.request
        check("the automatic answer is the usual length", probe.requests.count == 1 && auto?.length == .standard
              && !task(auto).contains("elaborate answer") && !task(auto).contains("quick answer"), task(auto))
        guard let line = model.lines.last else { return check("their question is in the transcript", false) }
        check("their question offers the three options", model.asksMe(line))

        model.answer(line: line, length: .detailed)
        let detailed = probe.last?.request
        check("Elaborate asks for the full in-depth answer", detailed?.length == .detailed && task(detailed).contains("rate limiter")
              && task(detailed).contains("elaborate answer") && task(detailed).contains("short limit doesn't apply"), task(detailed))
        model.answer(line: line, length: .quick)
        let quick = probe.last?.request
        check("Quick asks for a sentence or two", quick?.length == .quick && task(quick).contains("quick answer"), task(quick))
        check("the system prompt lets a requested length override the short default",
              detailed?.system.contains("Length follows the request") == true)
        check("an elaborate answer gets room on-device", LocalBudget.for(.answer, deep: false, length: .detailed).answer >= 3_000
              && LocalBudget.for(.answer, deep: false, length: .quick).answer < LocalBudget.for(.answer, deep: false).answer)

        model.inputText = "Explain this pubspec.lock file in detail"
        model.sendChat()
        let typed = probe.last?.request
        check("typing \"in detail\" asks for an elaborate answer", typed?.length == .detailed
              && task(typed).contains("I asked for detail"), task(typed))
        model.inputText = "what does sha256 mean here"
        model.sendChat()
        check("an ordinary typed question keeps the usual length", probe.last?.request.length == .standard
              && !task(probe.last?.request).contains("I asked for detail"), task(probe.last?.request))
        check("detail cues are recognized", Prompts.wantsDetail("can you elaborate on that") && Prompts.wantsDetail("Walk me through this config")
              && !Prompts.wantsDetail("what is a lockfile"))
        model.stopListening()
    }

    private static func echoes() async {
        print("\nNo headphones: their voice reaches my mic")
        let probe = Probe()
        let model = makeModel(probe)
        model.autoAnswer = false
        let question = "So what would you change about the on-call rotation if you had a free hand?"
        model.audio.onTranscript?(.them, .volatile("So what would you change about the on-call rotation"))
        model.audio.onTranscript?(.me, .volatile("so what would you change about the on call"))
        try? await Task.sleep(for: .milliseconds(100))
        check("the echo isn't shown as me speaking", model.volatile[.me] == nil, "volatile[me] = \(model.volatile[.me] ?? "nil")")
        // The mic cuts the utterance differently and mishears a word or two.
        model.audio.onTranscript?(.me, .final("what would you change about the uncle rotation"))
        model.audio.onTranscript?(.them, .final(question))
        model.audio.onTranscript?(.me, .final("rotation if you had a free hand"))
        try? await Task.sleep(for: .milliseconds(200))
        check("echoed lines stay out of the transcript", model.lines.map(\.speaker) == [.them],
              model.lines.map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n"))
        await say(model, .me, "I would move to follow the sun handoffs so nobody gets paged at night.")
        check("my real reply is kept as mine", model.lines.last?.speaker == .me && model.lines.count == 2,
              model.lines.map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n"))
        check("a reply that reuses a few of their words isn't an echo",
              !EchoFilter.isEcho("I would change the rotation to follow the sun", of: [question]))

        // No pause between their sentence ending and my reply: the mic hears it as one utterance.
        await say(model, .them, "And how would you roll that out across the other regions?", wait: 0.2)
        model.audio.onTranscript?(.me, .final("and how would you roll that out across the other regions I would start with one region and watch the pager load for a month"))
        try? await Task.sleep(for: .milliseconds(200))
        check("their sentence and mine in one mic utterance: mine is kept, theirs removed",
              model.lines.last?.speaker == .me && model.lines.last?.text.hasSuffix("I would start with one region and watch the pager load for a month") == true,
              model.lines.suffix(2).map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n"))
        // The mic's copy arrives before the call's own transcript of the same words.
        model.audio.onTranscript?(.me, .final("does that scale to twenty teams honestly not without splitting the rotation by service"))
        model.audio.onTranscript?(.them, .final("Does that scale to twenty teams?"))
        try? await Task.sleep(for: .milliseconds(200))
        check("same, when my mic's copy lands first", model.lines.contains { $0.speaker == .me && $0.text.hasSuffix("honestly not without splitting the rotation by service") }
              && !model.lines.contains { $0.speaker == .me && $0.text.lowercased().contains("twenty teams") },
              model.lines.suffix(3).map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n"))
        check("reusing a short phrase of theirs leaves my sentence whole",
              EchoFilter.withoutEcho("I think the rotation should follow the sun", of: ["What would you change about the rotation?"])
              == "I think the rotation should follow the sun")
        model.stopListening()
    }

    private static func ordering() async {
        print("\nI speak while their long turn is still being recognized")
        let probe = Probe()
        let model = makeModel(probe)
        model.autoAnswer = false
        model.audio.onTranscript?(.them, .volatile("Let me give you some background on the platform team first"))
        try? await Task.sleep(for: .milliseconds(400))
        model.audio.onTranscript?(.me, .volatile("Sure, go ahead please"))
        model.audio.onTranscript?(.me, .final("Sure, go ahead please, I have the document open."))
        try? await Task.sleep(for: .milliseconds(300))
        model.audio.onTranscript?(.them, .final("Let me give you some background on the platform team first, we own the deploy pipeline."))
        try? await Task.sleep(for: .milliseconds(100))
        check("the transcript reads in the order things were said", model.lines.map(\.speaker) == [.them, .me],
              model.lines.map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n"))
        model.stopListening()
    }

    private static func longMeeting() async {
        print("\nA meeting long enough that the transcript forgets its start")
        let probe = Probe()
        let model = makeModel(probe)
        model.autoAnswer = false
        await say(model, .them, "To start, what made you apply for this staff engineer role?", wait: 0.05)
        await say(model, .me, "I want to own reliability for a platform at this scale.", wait: 0.05)
        for index in 0..<270 {
            model.audio.onTranscript?(.them, .final("Update number \(index): the release went out on schedule."))
            model.audio.onTranscript?(.me, .final("Noted, thanks for update number \(index)."))
            if index % 30 == 0 { try? await Task.sleep(for: .milliseconds(20)) }
        }
        try? await Task.sleep(for: .milliseconds(300))
        await say(model, .them, "Going back to the beginning, does that still hold?", wait: 0.1)
        model.answerNow()
        let request = probe.last?.request
        check("the transcript was trimmed", model.lines.count <= 500
              && request?.text.components(separatedBy: "</transcript>").first?.contains("staff engineer role") == false,
              "lines: \(model.lines.count)")
        check("the memory still has the first question and my answer", state(request).contains("1. [0:00] They asked: To start, what made you apply")
              && state(request).contains("I said: I want to own reliability"), state(request))
        model.stopListening()
    }

    /// The tracker on its own, including Room mode (one mic, nobody labelled).
    private static func tracker() {
        print("\nTracker rules")
        let t0 = Date()
        func u(_ speaker: Speaker, _ text: String, _ at: Double) -> Utterance {
            Utterance(id: UUID(), speaker: speaker, text: text, start: t0.addingTimeInterval(at), updated: t0.addingTimeInterval(at + 2))
        }
        var s = ConversationState.build([
            u(.them, "How did you decide which service to migrate first?", 0),
            u(.them, "And how did you test it?", 3),
        ])
        check("two questions in one breath are one thing to answer", s.exchanges.count == 1
              && s.openTurn == "How did you decide which service to migrate first? And how did you test it?", "\(s)")

        s = ConversationState.build([
            u(.them, "We reorganized the platform group last quarter.", 0),
            u(.them, "What would you do in your first ninety days?", 60),
        ])
        check("an old statement isn't glued onto the new question", s.openTurn == "What would you do in your first ninety days?", "\(s)")

        s = ConversationState.build([
            u(.room, "What is our budget for the migration?", 0),
            u(.room, "About two hundred thousand for this year.", 4),
            u(.room, "And who signs off on it?", 9),
        ])
        check("Room mode: a statement after a question is its reply", s.exchanges.count == 2
              && s.exchanges[0].reply.contains("two hundred thousand") && s.openTurn == "And who signs off on it?", "\(s)")

        let line = u(.them, "I would love to hear about your last project.", 0)
        s = ConversationState.build([line], expectsReply: [line.id!])
        check("a request the model flagged counts as asked", s.exchanges.count == 1, "\(s)")
    }
}

/// `Assist --bench-mic`: starts the microphone with echo cancellation the way a meeting does
/// and reports whether macOS's voice processing came up and is delivering audio. Records
/// nothing; it only counts buffers for a few seconds.
enum MicBench {
    static func run() async {
        print("\n== Microphone with echo cancellation")
        guard await Permissions.microphone() else { print("  ✗ microphone access is off for this binary"); return }
        for cancelling in [false, true, false] {
            let mic = MicCapture()
            mic.echoCancellation = cancelling
            let counter = Counter()
            mic.onBuffer = { buffer in counter.add(buffer) }
            do { try await MainActor.run { try mic.start() } } catch {
                print("  ✗ \(cancelling ? "voice processing" : "plain") mic failed to start: \(error.localizedDescription)")
                continue
            }
            try? await Task.sleep(for: .seconds(3))
            let active = mic.isCancellingEcho
            await MainActor.run { mic.stop() }
            let (count, format, seconds) = counter.snapshot()
            print(String(format: "  %@ requested %@ · running %@ · %d buffers, %.1f s of audio · %@",
                         count > 0 && active == cancelling ? "✓" : "✗", cancelling ? "echo cancellation" : "plain mic",
                         active ? "with echo cancellation" : "plain", count, seconds, format))
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var frames = 0.0
        private var format = "no audio"
        func add(_ buffer: AVAudioPCMBuffer) {
            lock.withLock {
                count += 1
                frames += Double(buffer.frameLength) / buffer.format.sampleRate
                format = "\(Int(buffer.format.sampleRate)) Hz, \(buffer.format.channelCount) ch"
            }
        }
        func snapshot() -> (Int, String, Double) { lock.withLock { (count, format, frames) } }
    }
}

/// `Assist --bench-echo`: the no-headphones case, for real. Starts listening exactly as the
/// app does (call audio through ScreenCaptureKit, mic through `MicCapture`), then has another
/// process speak "their" lines out of the Mac's speakers while nobody talks into the mic.
/// Any of their words that end up under "You" are echo that got through. Runs once with echo
/// cancellation and once without, so the two layers can be told apart. Sends nothing.
@MainActor
enum EchoBench {
    private static let script = [
        "Thanks for joining today. I run the platform engineering group here.",
        "So tell me, how did you decide which service to migrate first?",
        "That makes sense. We had a similar problem with our billing system last year.",
        "What would you do differently if you had to run that migration again?",
    ]

    static func run() async {
        print("\n== Speakers, no headphones: does their voice end up in my half of the transcript?")
        for cancel in [true, false] {
            let suite = "com.sudhan.assist.bench"
            guard let defaults = UserDefaults(suiteName: suite) else { return }
            defaults.removePersistentDomain(forName: suite)
            let model = AppModel(defaults: defaults)
            model.provider = .claude
            model.speechEngine = .parakeet
            model.localeID = "en-US"
            model.captureSystemAudio = true
            model.echoCancellation = cancel
            var asked: [String] = []
            model.requestProbe = { title, _ in asked.append(title) }
            var flashes = 0
            model.startListening()
            let deadline = Date().addingTimeInterval(120)
            while !model.isListening, model.isStarting, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
            print("\n\(cancel ? "With" : "Without") echo cancellation · call audio captured: \(model.systemAudioActive) · mic cancelling: \(model.audio.micCancelsEcho)")
            if let notice = model.notice { print("  note: \(notice.text)") }
            guard model.isListening, model.systemAudioActive else {
                print("  ✗ can't run: the call's audio isn't being captured separately")
                model.stopListening()
                continue
            }
            try? await Task.sleep(for: .seconds(1))
            let t0 = Date()
            var played: [(Double, Double)] = []
            var micDuring: [Float] = [], micQuiet: [Float] = []
            for line in script {
                let began = Date().timeIntervalSince(t0)
                let speaking = Task.detached {
                    let say = Process()
                    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                    say.arguments = [line]
                    try? say.run()
                    say.waitUntilExit()
                }
                while !speaking.isCancelled {
                    if model.volatile[.me] != nil { flashes += 1 }
                    micDuring.append(model.micLevel)
                    if await Task.detached(operation: { await withTaskGroup(of: Bool.self) { group in
                        group.addTask { await speaking.value; return true }
                        group.addTask { try? await Task.sleep(for: .milliseconds(50)); return false }
                        let done = await group.next() ?? false
                        group.cancelAll()
                        return done
                    } }).value { break }
                }
                played.append((began, Date().timeIntervalSince(t0)))
                for _ in 0..<25 { micQuiet.append(model.micLevel); try? await Task.sleep(for: .milliseconds(100)) }
            }
            try? await Task.sleep(for: .seconds(3))
            print("  played: " + played.map { String(format: "%.1f–%.1f s", $0.0, $0.1) }.joined(separator: ", "))
            print(String(format: "  mic level while they play %.2f · between lines %.2f", micDuring.reduce(0, +) / Float(max(micDuring.count, 1)),
                         micQuiet.reduce(0, +) / Float(max(micQuiet.count, 1))))
            for line in model.lines {
                print(String(format: "  %5.1f–%5.1f s  %@ %@", line.start.timeIntervalSince(t0), line.updated.timeIntervalSince(t0),
                             line.speaker.label.padding(toLength: 5, withPad: " ", startingAt: 0), line.text))
            }
            // Anyone actually talking into the mic during the test is correctly "You"; only
            // lines made of the played words are echo that got through.
            let mine = model.lines.filter { $0.speaker == .me }
            let leaked = mine.filter { EchoFilter.isEcho($0.text, of: script) || EchoFilter.overlap($0.text, script.joined(separator: " ")) >= 0.6 }
            let theirs = model.lines.filter { $0.speaker == .them }.map(\.text).joined(separator: " ")
            let heard = EchoFilter.words(theirs)
            let spoken = EchoFilter.words(script.joined(separator: " "))
            print(String(format: "  %@ their words under \"You\": %d lines (%d words) · lines spoken into the mic by someone in the room: %d",
                         leaked.isEmpty ? "✓" : "✗", leaked.count, leaked.reduce(0) { $0 + $1.text.split(separator: " ").count },
                         mine.count - leaked.count))
            print(String(format: "  %@ their words captured: %d%% · questions picked up: %@",
                         heard.intersection(spoken).count * 10 >= spoken.count * 9 ? "✓" : "✗",
                         spoken.isEmpty ? 0 : heard.intersection(spoken).count * 100 / spoken.count, asked.description))
            model.stopListening()
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

import AVFoundation
import Foundation

/// `Assist --bench-e2e`: plays a synthesized meeting in real time through Parakeet into a real
/// `AppModel` running the on-device provider, and measures the number that matters: how long
/// after the other person stops talking the first word of the answer appears.
///
/// Uses its own settings domain, so it never touches the user's saved context or provider.
@MainActor
enum E2EBench {
    /// Their lines (spoken), and what you say back (injected as your mic's transcript).
    private static let script: [(text: String, expectsAnswer: Bool, reply: String?)] = [
        ("Thanks for joining. I'm Dana, and I run engineering here.", false, "Thanks for having me, great to meet you."),
        ("So tell me, how did you decide which service to migrate first?", true,
         "We started with the service that had the clearest boundary and the most pain."),
        ("Okay, that makes sense.", false, nil),
        ("I'd love to hear how you ran on-call for your last team.", true, "Sure. We had a weekly rotation with a primary and a secondary."),
        ("What would you do differently with eight years of hospital data?", true, nil),
    ]

    static func run() async {
        print("\n== End to end: their speech → transcript → first word of the answer")
        let suite = "com.sudhan.assist.bench"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = AppModel(defaults: defaults)
        model.profile = Sample.context.profile
        model.prerequisites = Sample.context.prerequisites
        model.notes = Sample.context.notes
        model.meetingContext = Sample.context.meeting
        model.localModelID = LocalModelSpec.recommended.id
        model.provider = .local
        let loadStart = Date()
        while model.localState != .ready {
            if case .failed(let message) = model.localState { print("  ✗ \(message)"); return }
            if model.localState == .notDownloaded { print("  ✗ \(model.localSpec.label) isn't downloaded"); return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        print(String(format: "%@ ready in %.1f s", model.localSpec.label, Date().timeIntervalSince(loadStart)))

        guard let (samples, starts, ends) = synthesize(script.map(\.text)) else { print("  ✗ couldn't synthesize speech"); return }
        let parakeet = ParakeetTranscriber { update in model.audio.onTranscript?(.them, update) }
        do { try await parakeet.start(locale: Locale(identifier: "en-US"), onStatus: nil) } catch {
            print("  ✗ Parakeet: \(error.localizedDescription)")
            return
        }
        model.isListening = true
        model.activeSpeechEngine = .parakeet
        model.sessionStart = Date()
        model.startSettling()

        let start = Date()
        var traces: [(time: Double, text: String)] = []
        model.trace = { traces.append((Date().timeIntervalSince(start), $0)) }

        // Feed audio at real-time pace off the main actor; watch the cards on it.
        let feeder = Task.detached(priority: .userInitiated) {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            var offset = 0
            while offset < samples.count {
                let count = min(320, samples.count - offset)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress! + offset, count: count) }
                parakeet.append(buffer)
                offset += count
                let wait = Double(offset) / 16_000 - Date().timeIntervalSince(start)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
        }
        var firstWord: [UUID: Double] = [:]
        var appeared: [UUID: Double] = [:]
        var replied = Set<Int>()
        while !feeder.isCancelled {
            let now = Date().timeIntervalSince(start)
            for card in model.cards {
                if appeared[card.id] == nil { appeared[card.id] = now }
                if firstWord[card.id] == nil, !card.text.trimmed.isEmpty { firstWord[card.id] = now }
            }
            for (index, line) in script.enumerated() where !replied.contains(index) && now > ends[index] + 2.2 {
                replied.insert(index)
                if let reply = line.reply { model.audio.onTranscript?(.me, .final(reply)) }
            }
            if now > Double(samples.count) / 16_000 + 4, !model.isGenerating { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        await feeder.value
        await parakeet.stop()

        var latencies: [Double] = []
        for (index, line) in script.enumerated() {
            let end = ends[index]
            let next = index + 1 < starts.count ? starts[index + 1] : .infinity
            // A card belongs to the line during which it appeared.
            let card = model.cards.first { card in
                guard let t = appeared[card.id] else { return false }
                return t >= starts[index] && t < next
            }
            let pathNotes = traces.filter { $0.time >= starts[index] && $0.time < next }.map(\.text)
            print("\n\(line.expectsAnswer ? "Q" : "·") \"\(line.text)\"")
            if !pathNotes.isEmpty { print("   harness: " + pathNotes.joined(separator: " → ")) }
            guard let card, let shown = firstWord[card.id] else {
                print(line.expectsAnswer ? "   ✗ no answer" : "   ✓ no answer (none needed)")
                continue
            }
            let latency = shown - end
            if line.expectsAnswer { latencies.append(latency) }
            print(String(format: "   %@ first word %.0f ms after they stopped talking%@", line.expectsAnswer ? "✓" : "✗ (unneeded)",
                         latency * 1000, card.stats.map { " · " + $0 } ?? ""))
            if let detail = model.statsDetail[card.id] { print("   timing: " + detail) }
            print("   ┆ " + card.text.prefix(220).replacingOccurrences(of: "\n", with: "\n   ┆ "))
        }
        if !latencies.isEmpty {
            let sorted = latencies.sorted()
            print(String(format: "\nEnd of speech → first answer word: median %.0f ms, worst %.0f ms (%d questions)",
                         sorted[sorted.count / 2] * 1000, (sorted.last ?? 0) * 1000, sorted.count))
        }
        model.stopListening()
        await LocalEngine.shared.unload()
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0 == " " }
    }

    /// Renders each line with macOS `say` and joins them with 3 s gaps.
    static func synthesize(_ lines: [String]) -> ([Float], [TimeInterval], [TimeInterval])? {
        var samples = [Float](repeating: 0, count: 8_000)
        var starts: [TimeInterval] = []
        var ends: [TimeInterval] = []
        for (index, text) in lines.enumerated() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("assist-e2e-\(index).wav")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "--data-format=LEF32@16000", text]
            guard (try? say.run()) != nil else { return nil }
            say.waitUntilExit()
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData?[0] else { return nil }
            var speech = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
            while let last = speech.last, abs(last) < 0.004 { speech.removeLast() }
            starts.append(Double(samples.count) / 16_000)
            samples += speech
            ends.append(Double(samples.count) / 16_000)
            samples += [Float](repeating: 0, count: 56_000)
        }
        return (samples, starts, ends)
    }
}

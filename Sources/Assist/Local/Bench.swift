import Foundation
import MLX

/// `Assist --bench[=model-id]` measures the on-device LLM pipeline on this Mac and prints a
/// report; `--bench-stt` does the same for speech recognition, and `--bench-e2e` measures the
/// whole app from someone's speech to the first word of the answer. Both run headless: launch the
/// binary inside the app bundle directly to see the output.
enum Bench {
    static func run(_ arguments: [String]) async {
        let llm = arguments.contains { $0 == "--bench" || $0.hasPrefix("--bench=") }
        let stt = arguments.contains("--bench-stt")
        let e2e = arguments.contains("--bench-e2e")
        print("Assist bench · \(ProcessInfo.processInfo.physicalMemory >> 30) GB · \(Host.current().localizedName ?? "")")
        if llm { await runLLM(arguments) }
        if stt { await STTBench.run() }
        if e2e { await E2EBench.run() }
    }

    private static func runLLM(_ arguments: [String]) async {
        let requested = arguments.first { $0.hasPrefix("--bench=") }.map { String($0.dropFirst("--bench=".count)) }
        let specs = requested.map { [LocalModelSpec.named($0)] } ?? LocalModelSpec.all.filter(\.isDownloaded)
        for spec in specs {
            do { try await bench(spec) } catch { print("  ✗ \(spec.label): \(error.localizedDescription)") }
        }
    }

    private static func bench(_ spec: LocalModelSpec) async throws {
        let engine = LocalEngine.shared
        print("\n== \(spec.label) (\(spec.repo))")
        var clock = Date()
        try await engine.load(spec)
        print(String(format: "load + kernel warm-up: %.2f s · MTP head: %@ · GPU memory %d MB",
                     Date().timeIntervalSince(clock), await engine.usesMTP ? "yes" : "no", Memory.activeMemory >> 20))

        let (template, manual) = try await engine.templateTokens(system: "Be brief.", user: "Hello there")
        print("chat template matches hand-rendered prompt: \(template == manual ? "yes" : "NO (\(template.count) vs \(manual.count) tokens)")")

        for chunk in [64, 256, 512, 1024, 2048] {
            let rate = await engine.measurePrefill(count: 2048, chunk: chunk)
            print(String(format: "raw prefill, 2048 tokens in chunks of %4d: %5.0f tok/s", chunk, rate))
        }

        let system = Prompts.system(Sample.context)
        let settled = Sample.lines.enumerated().map { PrefixLine(key: UUID(), text: $0.element) }
        let question = "So, thinking about the migration you led: how did you decide what to move first, and what would you do differently?"
        let tail = Prompts.localTail(recentLines: ["[14:02] Them: \(question)"],
                                     task: Prompts.localAnswerTask)
        let prompt = LocalPrompt(system: system, settled: settled, tail: tail)

        // Cold: what a stateless local server does on every request — prefill everything.
        await engine.resetWarm()
        let cold = try await answer(engine, prompt, label: "cold (full prefill)")

        // Warm: the transcript was prefilled in the background while people talked.
        await engine.resetWarm()
        clock = Date()
        await engine.sync(system: system, settled: settled, background: true)
        let (warmTokens, warmLines, _) = await engine.diagnostics()
        print(String(format: "background prefill of %d tokens (%d lines): %.2f s (%.0f tok/s)", warmTokens, warmLines,
                     Date().timeIntervalSince(clock), Double(warmTokens) / Date().timeIntervalSince(clock)))
        let warm = try await answer(engine, prompt, label: "warm prefix + MTP")
        print(String(format: "→ time to first word: %.0f ms cold vs %.0f ms warm (%.1fx)",
                     cold.firstTokenSeconds * 1000, warm.firstTokenSeconds * 1000,
                     cold.firstTokenSeconds / max(warm.firstTokenSeconds, 1e-3)))

        if await engine.usesMTP {
            await engine.setMTP(false)
            let plain = try await answer(engine, prompt, label: "warm, plain decoding")
            await engine.setMTP(true)
            print(String(format: "→ MTP decode speedup: %.2fx (%.0f vs %.0f tok/s)", warm.tokensPerSecond / max(plain.tokensPerSecond, 1),
                         warm.tokensPerSecond, plain.tokensPerSecond))
        }

        // PredGen: draft while they're still talking, then verify against the final transcript.
        let cases: [(String, String, String)] = [
            ("only punctuation differs", "What's your take on monorepos for a team our size", "What's your take on monorepos for a team our size?"),
            ("ASR adds the last word", "So how did you decide which service to move", "So how did you decide which service to move first?"),
            ("they add a clause", "So how did you decide which service to move first?",
             "So how did you decide which service to move first? Like, was it risk or traffic?"),
            ("question changes", "So, thinking about the migration you led",
             "So, thinking about the migration you led: what would you do differently with hospital data?"),
        ]
        for (name, partial, final) in cases {
            let draftTail = Prompts.localTail(recentLines: ["[14:02] Them: \(partial)"],
                                              task: Prompts.localAnswerTask)
            let finalTail = Prompts.localTail(recentLines: ["[14:02] Them: \(final)"],
                                              task: Prompts.localAnswerTask)
            let draftID = UUID()
            let draft = EventLog()
            _ = try await engine.generate(LocalPrompt(system: system, settled: settled, tail: draftTail),
                                          id: draftID, continuing: nil, maxTokens: 160) { draft.record($0) }
            let resumed = EventLog()
            _ = try await engine.generate(LocalPrompt(system: system, settled: settled, tail: finalTail),
                                          id: UUID(), continuing: draftID, maxTokens: 220) { resumed.record($0) }
            print(String(format: "PredGen · %@: kept %d/%d chars of the draft, shown after %.0f ms; next new word at %.0f ms",
                         name, resumed.replaced.count, draft.text.count, resumed.replacedAfter * 1000,
                         resumed.stats.firstTokenSeconds * 1000))
        }

        // Turn check (SpeculativeETD verifier stage).
        for utterance in ["I'd love to hear how you handled on-call at your last job.",
                          "Okay, let me share my screen real quick.",
                          "What's your take on monorepos?"] {
            clock = Date()
            let p = await engine.expectsReply(LocalPrompt(system: system, settled: settled,
                                                          tail: Prompts.turnCheckTail(recentLines: ["[14:05] Them: \(utterance)"])))
            print(String(format: "turn check %.0f ms · p(reply)=%.2f · \"%@\"", Date().timeIntervalSince(clock) * 1000, p ?? -1, utterance))
        }
        print(String(format: "GPU memory now %d MB (peak %d MB)", Memory.activeMemory >> 20, Memory.peakMemory >> 20))
        await engine.unload()
    }

    private static func answer(_ engine: LocalEngine, _ prompt: LocalPrompt, label: String) async throws -> LocalStats {
        let log = EventLog()
        _ = try await engine.generate(prompt, id: UUID(), continuing: nil, maxTokens: 220) { log.record($0) }
        let stats = log.stats
        let acceptance = stats.draftAcceptance.map { String(format: " · MTP acceptance %.0f%%", $0 * 100) } ?? ""
        print(String(format: "%@: first word %.0f ms · prefill %d tok (reused %d) · %.1f tok/s · %d tokens%@",
                     label, stats.firstTokenSeconds * 1000, stats.prefillTokens, stats.reusedTokens,
                     stats.tokensPerSecond, stats.generatedTokens, acceptance))
        if label.hasPrefix("warm prefix") { print("   ┆ " + log.text.replacingOccurrences(of: "\n", with: "\n   ┆ ")) }
        return stats
    }
}

/// Collects a generation's events; the engine calls back on its own queue.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private let start = Date()
    private var _text = ""
    private var _replaced = ""
    private var _replacedAfter = 0.0
    private var _stats = LocalStats()

    var text: String { lock.withLock { _text } }
    var replaced: String { lock.withLock { _replaced } }
    var replacedAfter: Double { lock.withLock { _replacedAfter } }
    var stats: LocalStats { lock.withLock { _stats } }

    func record(_ event: LocalEvent) {
        lock.withLock {
            switch event {
            case .delta(let chunk): _text += chunk
            case .replace(let all):
                _text = all
                _replaced = all
                _replacedAfter = Date().timeIntervalSince(start)
            case .finished(let stats): _stats = stats
            }
        }
    }
}

/// A realistic interview transcript, long enough that prefill cost matters.
enum Sample {
    static let context = PromptContext(
        profile: """
        Staff software engineer, 9 years. At Fennel (logistics SaaS, 2021–now) I led the migration of our order pipeline from a Rails monolith to Go services on Kubernetes: 14 services, zero-downtime cutover over 7 months, p99 latency from 1.8 s to 240 ms, infra cost down 31%. Before that, 4 years at Brightwave (payments), where I built the reconciliation engine (Kafka + Postgres) processing 40M transactions/day and ran the on-call rotation for a team of 8. Comfortable with Go, Rust, Postgres, Kafka, Terraform. Mentored 6 engineers to senior. Biggest mistake: underestimating the data backfill for the migration, which slipped us 5 weeks.
        """,
        prerequisites: """
        Role: Principal Engineer, Platform at Northwind Health. They're splitting a Django monolith that serves 200 hospitals; HIPAA constraints; team of 30 engineers; looking for someone to own the migration strategy and reliability (SLOs, incident response).
        """,
        notes: "Answer in first person. Max 4 bullets. Prefer concrete numbers from my background.",
        meeting: "Final-round interview with the VP of Engineering (Dana) and a staff engineer (Raj).")

    static let lines: [String] = {
        let turns: [(String, String)] = [
            ("Them", "Thanks for making the time today. I'm Dana, I run engineering here, and Raj is one of our staff engineers on the platform team."),
            ("Me", "Great to meet you both. Thanks for having me."),
            ("Them", "So just to set the stage, we're about thirty engineers, mostly on one big Django application that serves around two hundred hospitals."),
            ("Them", "It's grown for eight years and deploys are getting scary. We ship twice a week and every release needs a manual QA pass."),
            ("Me", "That sounds familiar. At Fennel we were on a Rails monolith with very similar symptoms before we split out the order pipeline."),
            ("Them", "Yeah, Raj read your write-up on that. Raj, do you want to start?"),
            ("Them", "Sure. I'm curious about the technical side first. What did the architecture look like before you started?"),
            ("Me", "One Rails app, one big Postgres, and a pile of Sidekiq jobs. Orders, billing and routing all shared tables, which was the real problem."),
            ("Them", "And how did you get buy-in to spend seven months on that? That's a long time without features."),
            ("Me", "We tied it to two things the business cared about: checkout latency, which was costing us conversions, and the infra bill, which was growing faster than revenue."),
            ("Them", "Makes sense. We have a similar pressure on cost, especially since we're on dedicated HIPAA hosting."),
            ("Them", "Let's talk about reliability for a bit. Today we don't really have SLOs. We have alerts that page whoever's awake."),
            ("Me", "We had that too at Brightwave early on. Alerting on symptoms instead of causes was the first big shift."),
            ("Them", "Can you say more about what you mean by symptoms versus causes?"),
            ("Me", "Page on what users feel, like error rate and latency on key journeys, and put CPU or queue depth on dashboards instead of pagers."),
            ("Them", "Got it. How big was the on-call rotation there?"),
            ("Me", "Eight people, weekly primary and secondary, and we capped it so nobody was primary more than once every six weeks."),
            ("Them", "And incident reviews? Blameless?"),
            ("Me", "Blameless, written within three days, with action items that had owners and due dates. We tracked completion monthly."),
            ("Them", "Okay. Switching gears. Our biggest worry with splitting the monolith is the data. Everything joins against the patients table."),
            ("Them", "Some people want to do a big-bang rewrite of the scheduling module. Others want to strangle it piece by piece."),
            ("Me", "I'd almost always strangle it. Big-bang rewrites hide risk until the cutover, and with hospitals you can't afford a bad cutover."),
            ("Them", "Raj is in the strangler camp too. The pushback is that it takes longer."),
            ("Me", "It does take longer on paper, but you deliver value along the way and you can stop at any point with a working system."),
            ("Them", "What about the shared database? Did you split the data at Fennel or keep one Postgres?"),
            ("Me", "We split it, but late. We kept a shared database for the first three services and used views to enforce ownership, then moved tables out one at a time."),
            ("Them", "And the backfill, I think you mentioned it slipped."),
            ("Me", "Yes, the order history backfill took five weeks longer than planned because of inconsistent legacy data. I'd budget for that up front next time."),
            ("Them", "That's honest, thank you. We'll definitely hit that with eight years of hospital data."),
            ("Them", "Let me ask about people for a second. You'd be working with thirty engineers, most of whom have only worked on Django."),
            ("Me", "I'd want a small platform team that builds the paved road, and then embed with product teams for their first service."),
            ("Them", "How did that go at Fennel? Did the product teams resist?"),
            ("Me", "Some did. What worked was making the first migrated service clearly better to work on, with faster deploys and better local dev."),
            ("Them", "Right. Developer experience as the carrot."),
            ("Them", "Okay, Raj has a couple of deeper technical ones, and then we'll leave time for your questions."),
            ("Them", "Sure. How did you handle cross-service transactions? Orders and billing must have needed to stay consistent."),
            ("Me", "Outbox pattern plus idempotent consumers. Each service wrote events to an outbox table in the same transaction and a relay published them to Kafka."),
            ("Them", "And when consumers failed?"),
            ("Me", "Retries with backoff, then a dead letter topic with an alert and a replay tool. We reconciled nightly as a safety net."),
            ("Them", "That's close to what we sketched. Did you run into ordering issues?"),
            ("Me", "A few. We partitioned by order ID so events for one order stayed in order, and made handlers tolerant of duplicates."),
            ("Them", "Nice. Dana, back to you."),
            ("Them", "Thanks Raj. I want to come back to the migration itself, because that's really the heart of this role."),
        ]
        return turns.enumerated().map { index, turn in
            let seconds = 30 + index * 19
            return String(format: "[%d:%02d] %@: %@", seconds / 60, seconds % 60, turn.0, turn.1)
        }
    }()
}

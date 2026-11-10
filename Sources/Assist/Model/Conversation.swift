import Foundation

/// One piece of speech as the conversation tracker sees it: a transcript line, or words
/// still being spoken.
struct Utterance {
    var id: UUID?
    var speaker: Speaker
    var text: String
    var start: Date
    var updated: Date
}

/// Something the other side asked (or asked for), and what was said back.
struct Exchange: Equatable {
    var question: String
    var askedAt: Date
    /// What I said after it. In Room mode (one mic, no speaker labels) it's whatever was said next.
    var reply = ""
    var fromRoom = false

    var answered: Bool { !reply.isEmpty }
}

/// Where the conversation stands right now.
enum Focus: Equatable {
    case none
    /// They spoke last and I haven't responded. `exchange` indexes the question this turn
    /// opened or added to, if it was one.
    case theirTurn(text: String, exchange: Int?)
    /// I spoke last. `exchange` is the question I was answering, if any.
    case myTurn(said: String, exchange: Int?)
}

/// Assist's running memory of the meeting: every question the other side has asked, in order,
/// with what I said back, plus who holds the floor now. It's rebuilt from the transcript on
/// demand, so echo removal, merged lines and late punctuation can never leave it stale, and
/// it's far smaller than the transcript, so the first question survives a long meeting.
struct ConversationState: Equatable {
    var exchanges: [Exchange] = []
    var focus = Focus.none

    /// The other side's current turn, when they're the ones waiting.
    var openTurn: String? {
        if case .theirTurn(let text, _) = focus { return text }
        return nil
    }

    /// Lines of one turn that are this far apart are separate thoughts: a statement from a
    /// while ago isn't part of the question they just asked.
    static let turnGap: TimeInterval = 8

    /// - Parameters:
    ///   - earlier: exchanges from transcript lines that have since been trimmed away.
    ///   - expectsReply: lines the model judged to be waiting on me though they aren't phrased as questions.
    static func build(_ utterances: [Utterance], earlier: [Exchange] = [], expectsReply: Set<UUID> = []) -> ConversationState {
        var exchanges = earlier
        /// Their lines since I last said something of substance.
        var run: [Utterance] = []
        /// The exchange their current turn opened or added to.
        var runExchange: Int?
        var mine = ""
        var iSpokeLast = false

        for utterance in utterances {
            let text = utterance.text.trimmed
            guard !text.isEmpty else { continue }

            if utterance.speaker == .me {
                // "Mm-hm" while they talk neither answers anything nor ends their turn.
                if Backchannel.matches(text) { continue }
                if !iSpokeLast { mine = "" }
                mine = mine.isEmpty ? text : mine + " " + text
                if let last = exchanges.indices.last { exchanges[last].reply = Self.joined(exchanges[last].reply, text) }
                iSpokeLast = true
                run = []
                runExchange = nil
                continue
            }

            // "Right, okay" while I'm answering doesn't take the floor back.
            if iSpokeLast, Backchannel.matches(text) { continue }
            let asks = QuestionDetector.isQuestion(text) || utterance.id.map(expectsReply.contains) == true
            let sameTurn = !iSpokeLast && !run.isEmpty
            iSpokeLast = false

            if utterance.speaker == .room, !asks, let last = exchanges.indices.last {
                // One microphone for everyone: a statement after a question is the reply to it.
                exchanges[last].reply = Self.joined(exchanges[last].reply, text)
                run = []
                runExchange = nil
                continue
            }
            if !sameTurn { run = []; runExchange = nil }
            run.append(utterance)

            if let open = runExchange {
                // Same turn, still talking: the question grows ("…and how would you test it?").
                exchanges[open].question = Self.joined(exchanges[open].question, text)
            } else if asks {
                exchanges.append(Exchange(question: text, askedAt: utterance.start, fromRoom: utterance.speaker == .room))
                runExchange = exchanges.count - 1
            }
        }

        var state = ConversationState(exchanges: exchanges)
        if iSpokeLast {
            state.focus = .myTurn(said: mine, exchange: exchanges.indices.last)
        } else if !run.isEmpty {
            state.focus = .theirTurn(text: turnText(run), exchange: runExchange)
        }
        return state
    }

    /// The end of their turn that hangs together: back from the newest line while the lines
    /// follow each other closely.
    private static func turnText(_ run: [Utterance]) -> String {
        var parts: [String] = []
        var next: Utterance?
        for utterance in run.reversed() {
            if let next, next.start.timeIntervalSince(utterance.updated) > turnGap { break }
            parts.insert(utterance.text.trimmed, at: 0)
            next = utterance
            if parts.count >= 6 { break }
        }
        return String(parts.joined(separator: " ").suffix(900))
    }

    private static func joined(_ a: String, _ b: String) -> String {
        a.isEmpty ? b : a + " " + b
    }

    // MARK: Prompt

    /// The memory as the model reads it. The first question always stays, with the most
    /// recent ones; a long middle is summarized by count.
    func rendered(stamp: (Date) -> String, recent: Int = 7) -> String {
        guard !exchanges.isEmpty else { return "" }
        var rows: [String] = []
        let cut = exchanges.count > recent + 1 ? exchanges.count - recent : 1
        for (index, exchange) in exchanges.enumerated() {
            if index >= 1 && index < cut {
                if index == 1 { rows.append("(… \(cut - 1) more question\(cut == 2 ? "" : "s") in between, still in the transcript if it reaches that far …)") }
                continue
            }
            let asker = exchange.fromRoom ? "Asked" : "They asked"
            let replier = exchange.fromRoom ? "Said in reply" : "I said"
            rows.append("\(index + 1). [\(stamp(exchange.askedAt))] \(asker): \(exchange.question.clipped(320))")
            rows.append("   \(replier): \(exchange.answered ? exchange.reply.clipped(360) : "(nothing yet)")")
        }
        switch focus {
        case .theirTurn(_, let exchange?):
            rows.append("Now: they are waiting on my answer to #\(exchange + 1).")
        case .theirTurn(_, nil):
            rows.append("Now: they spoke last. It wasn't phrased as a question.")
        case .myTurn(_, let exchange?):
            rows.append("Now: I am in the middle of answering #\(exchange + 1).")
        case .myTurn(_, nil), .none:
            break
        }
        return rows.joined(separator: "\n")
    }
}

/// Short listener noises ("mm-hm", "yeah, okay") that don't take a turn.
enum Backchannel {
    private static let words: Set<String> = [
        "yeah", "yes", "yep", "yup", "ok", "okay", "right", "sure", "mm", "mhm", "mmhm", "hmm", "hm", "uh", "um",
        "huh", "oh", "ah", "i", "see", "got", "it", "cool", "great", "nice", "alright", "exactly", "true", "so",
        "well", "and", "mm-hm", "uh-huh", "gotcha", "understood", "perfect", "good", "makes", "sense", "that",
    ]

    static func matches(_ text: String) -> Bool {
        if text.contains("?") { return false }
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" })
        return !tokens.isEmpty && tokens.count <= 4 && tokens.allSatisfy { words.contains(String($0)) }
    }
}

extension String {
    /// Shortens long text by dropping its middle: how a question starts and how it ends both matter.
    func clipped(_ limit: Int) -> String {
        guard count > limit else { return self }
        let half = (limit - 3) / 2
        return String(prefix(half)).trimmed + " … " + String(suffix(half)).trimmed
    }
}

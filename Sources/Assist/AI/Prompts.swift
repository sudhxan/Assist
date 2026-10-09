import Foundation

/// Everything the user typed into Settings → Context.
struct PromptContext {
    var profile: String
    var prerequisites: String
    var notes: String
    var meeting: String
}

enum Prompts {
    private static let base = """
    You are Assist, a discreet real-time copilot that lives in the user's MacBook notch during meetings and calls. You get a rolling speech-to-text transcript of the conversation and help the user understand it and respond well in the moment.

    Transcript speakers: "Them" is the other participants (heard through the computer's audio), "Me" is the user's microphone, and "Room" is a single microphone that may pick up anyone. Speech recognition makes mistakes, so infer the intended words from context rather than commenting on errors.

    The user reads your reply at a glance while someone is talking, so:
    - Lead with the substance. No greeting, no restating the question, no "Great question".
    - When the user needs to say something, write it in first person, in natural spoken language they can say out loud.
    - Keep it short: usually 2–4 bullets of at most about 20 words each. Bold the two to four key words in each bullet so the reply can be skimmed in a second.
    - Be concrete: numbers, names, trade-offs, examples. If you aren't sure of a fact, say so briefly instead of guessing.
    - Ground personal claims (experience, employers, projects, metrics) only in <about_me>. If something isn't there, keep it general or leave a placeholder like [your example] — never invent personal facts.
    - Treat <prerequisites> as background the user prepared before the meeting (for example a job description, agenda, product facts, or documents). Draw on it, and prefer it over general knowledge when they disagree.
    - Use Markdown sparingly: bullets, **bold**, `inline code`, and short fenced code blocks only when code is actually needed.
    """

    static func system(_ context: PromptContext, local: Bool = false) -> String {
        var prompt = base
        if local {
            prompt += "\n- Transcript rows from \"Assist (suggested to me)\" are your own earlier suggestions to me, which I may or may not have used. Don't repeat them unless asked."
        }
        func add(_ tag: String, _ value: String, preface: String? = nil) {
            let text = value.trimmed
            guard !text.isEmpty else { return }
            prompt += "\n\n<\(tag)>\n"
            if let preface { prompt += preface + "\n\n" }
            prompt += "\(text)\n</\(tag)>"
        }
        add("about_me", context.profile)
        add("prerequisites", context.prerequisites)
        add("meeting_context", context.meeting)
        add("user_instructions", context.notes,
            preface: "The user's own standing instructions for how you should respond. Follow them; where they conflict with the default style above, they win.")
        return prompt
    }

    /// The on-device layout puts the transcript first and the task last, so everything up to the
    /// newest settled line is a stable prefix the engine keeps prefilled. This tail closes the
    /// transcript opened by the warm prefix.
    static func localTail(recentLines: [String], task: String) -> String {
        recentLines.map { $0 + "\n" }.joined() + "</transcript>" + closing(task: task, recent: "")
    }

    /// Doesn't quote the question: it's already the transcript's last line. Keeping the task
    /// fixed means a draft started mid-sentence and the final request differ only in the
    /// words that arrived since, which is what lets the draft's prefix be reused.
    static let localAnswerTask = "Give me what to say in response to the last thing they said or asked."

    /// Asks the model whether the last utterance is waiting on the user. The engine reads the
    /// probability of "Yes" from a single forward pass.
    static func turnCheckTail(recentLines: [String]) -> String {
        recentLines.map { $0 + "\n" }.joined() + """
        </transcript>

        Does the last line from Them (or Room) ask me something, or clearly expect me to respond now? Answer Yes or No.
        """
    }

    static func user(task: String, transcript: String, recent: String) -> String {
        "<transcript>\n\(transcript)\n</transcript>" + closing(task: task, recent: recent)
    }

    /// What follows the transcript: Assist's recent replies (if any), then the task.
    private static func closing(task: String, recent: String) -> String {
        var text = ""
        if !recent.isEmpty {
            text += "\n\n<your_recent_replies>\n\(recent)\n</your_recent_replies>"
        }
        return text + "\n\n<task>\n\(task)\n</task>"
    }

    static func answerTask(question: String?) -> String {
        guard let question else {
            return "Based on the latest exchange, tell me what to say next."
        }
        return "They just asked or said:\n\"\"\"\n\(question)\n\"\"\"\nGive me what to say in response."
    }

    static let recapTask = """
    Recap the conversation so far: 3–5 bullets of the key points, then **Decisions** and **Action items** (with owners if mentioned). Leave out any section that would be empty.
    """

    static let followUpTask = """
    Suggest 3 sharp things I could say or ask next to move the conversation forward. One line each, phrased exactly as I'd say them.
    """

    static let explainTask = """
    Find the most recent technical term, concept, acronym, or claim in the conversation that I might not fully know, and explain it plainly: a one-line definition, why it matters here, and one sentence I could say to show I understand it.
    """

    static func chatTask(_ text: String) -> String {
        "I typed this privately (it is not part of the conversation): \(text)\n\nAnswer it, using the conversation for context when it's relevant."
    }

    /// The on-device model reads the screen through OCR rather than pixels.
    static func screenTextTask(_ text: String, typed: String) -> String {
        "This is the text on my screen right now, read by OCR (layout is approximate):\n<screen>\n\(text.isEmpty ? "(no readable text)" : String(text.prefix(12_000)))\n</screen>\n\n\(screenAsk(typed))"
    }

    static func screenTask(_ typed: String) -> String {
        "The attached image is a screenshot of my screen right now. \(screenAsk(typed))"
    }

    private static func screenAsk(_ typed: String) -> String {
        typed.isEmpty
            ? "If there's a question, problem, or code on it, help me answer or solve it. Otherwise tell me what on it matters for this conversation."
            : "My request: \(typed)"
    }
}

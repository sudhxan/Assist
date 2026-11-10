import Foundation

enum NotchState: Equatable {
    case collapsed, peek, expanded
}

enum Speaker: String, Hashable, Sendable {
    /// Your microphone, when system audio is captured separately.
    case me
    /// Other participants, heard through the Mac's audio output.
    case them
    /// Microphone only — could be anyone in the room.
    case room

    var label: String {
        switch self {
        case .me: "You"
        case .them: "Them"
        case .room: "Room"
        }
    }

    var promptLabel: String {
        switch self {
        case .me: "Me"
        case .them: "Them"
        case .room: "Room"
        }
    }
}

struct TranscriptLine: Identifiable, Equatable {
    let id = UUID()
    var speaker: Speaker
    var text: String
    var start: Date
    var updated: Date
    /// Order in which lines entered the transcript; never reused, even after lines are removed.
    var seq = 0
}

enum CardKind: String {
    case answer, screen, recap, followUps, explain, chat

    var label: String {
        switch self {
        case .answer: "Answer"
        case .screen: "Screen"
        case .recap: "Recap"
        case .followUps: "Follow-ups"
        case .explain: "Explain"
        case .chat: "Ask"
        }
    }

    var symbol: String {
        switch self {
        case .answer: "sparkles"
        case .screen: "camera.viewfinder"
        case .recap: "list.bullet.rectangle.portrait"
        case .followUps: "lightbulb.max"
        case .explain: "text.book.closed"
        case .chat: "bubble.left.and.text.bubble.right"
        }
    }
}

/// How much of an answer I want. Every question from the other side offers all three; the
/// automatic answer is `.standard`.
enum AnswerLength: String, CaseIterable, Sendable {
    case quick, standard, detailed

    var label: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Explain"
        case .detailed: "Elaborate"
        }
    }

    var symbol: String {
        switch self {
        case .quick: "bolt.fill"
        case .standard: "text.alignleft"
        case .detailed: "text.book.closed.fill"
        }
    }

    var help: String {
        switch self {
        case .quick: "Quick answer: a sentence or two to say right now"
        case .standard: "Answer with a quick explanation: a few key points"
        case .detailed: "Elaborate answer: the full, in-depth version"
        }
    }
}

struct AnswerCard: Identifiable, Equatable {
    enum Phase: Equatable {
        case streaming, done, failed(String)
    }

    var id = UUID()
    var kind: CardKind
    var title: String
    /// The instruction sent to the model, kept so the card can be regenerated.
    var task: String
    var imageJPEG: Data?
    /// A problem to solve, answered with more reasoning and room (kept for "Try again").
    var deep = false
    var length = AnswerLength.standard
    /// The transcript line this answers, so its Quick / Explain / Elaborate options find it.
    var lineID: UUID?
    var text = ""
    /// Shown while the model reasons before its answer, e.g. "Thinking · 512 tokens".
    var thinking: String?
    var phase: Phase = .streaming
    /// Short "provider · model" label shown under the answer.
    var modelLabel: String
    /// On-device latency, e.g. "120 ms to first word · 66 tok/s".
    var stats: String?
    var created = Date()

    var failed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case context = "Context"
    case ai = "AI model"
    case general = "General"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .context: "text.document"
        case .ai: "cpu"
        case .general: "slider.horizontal.3"
        }
    }
}

enum BuddyMood: Equatable {
    case sleeping, drowsy, waking, idle, listening, alert, thinking, happy
}

/// How sleepy the buddy is while the notch is closed.
enum SleepPhase: Equatable {
    case awake, drowsy, asleep
}

/// Places in the notch where the one buddy can sit.
enum BuddySpot: Hashable {
    case ear, header, welcome, transcript, answer
}

struct Notice: Equatable {
    enum Action: Equatable {
        case microphonePrivacy, screenRecordingPrivacy, apiKeySettings, languageSettings
    }

    var text: String
    var action: Action?
    var isError = true
}

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case local, claude, openRouter, gemini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: "On-device"
        case .claude: "Claude"
        case .openRouter: "OpenRouter"
        case .gemini: "Gemini"
        }
    }

    var isLocal: Bool { self == .local }

    var keychainAccount: String {
        switch self {
        case .local: ""
        case .claude: "anthropic-api-key"
        case .openRouter: "openrouter-api-key"
        case .gemini: "gemini-api-key"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .local: ""
        case .claude: "Paste Claude API key (sk-ant-…)"
        case .openRouter: "Paste OpenRouter key (sk-or-…)"
        case .gemini: "Paste Gemini API key (AIza…)"
        }
    }

    var keySource: String {
        switch self {
        case .local: ""
        case .claude: "console.anthropic.com"
        case .openRouter: "openrouter.ai/keys"
        case .gemini: "aistudio.google.com/apikey"
        }
    }

    var defaultModel: String {
        switch self {
        case .local: LocalModelSpec.recommended.id
        case .claude: ClaudeModel.all[0].id
        case .openRouter: "anthropic/claude-sonnet-5.5"
        case .gemini: "gemini-3.8-flash"
        }
    }
}

/// Which speech recognizer transcribes the meeting.
enum SpeechEngine: String, CaseIterable, Identifiable, Sendable {
    /// NVIDIA Parakeet Unified 0.6B on the Neural Engine. English only.
    case parakeet
    /// Apple's SpeechAnalyzer. Every language macOS supports.
    case apple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parakeet: "Parakeet"
        case .apple: "Apple"
        }
    }
}

/// Where the on-device model is in its lifecycle.
enum LocalModelState: Equatable {
    case notDownloaded
    case downloading(Double)
    case downloaded
    case loading
    case ready
    case failed(String)
}

struct ClaudeModel: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    /// Accepts server-side refusal fallbacks. Every model here accepts `output_config.effort`.
    let fallbacks: Bool

    /// Opus 5.5 leads: the strongest model that still answers at conversation speed. Fable 5.2
    /// is the most capable, for when depth matters more than the first second; Haiku 5.5 is
    /// the quickest.
    static let all: [ClaudeModel] = [
        ClaudeModel(id: "claude-opus-5-5", label: "Opus 5.5", fallbacks: true),
        ClaudeModel(id: "claude-fable-5-2", label: "Fable 5.2", fallbacks: true),
        ClaudeModel(id: "claude-sonnet-5-5", label: "Sonnet 5.5", fallbacks: true),
        ClaudeModel(id: "claude-haiku-5-5", label: "Haiku 5.5", fallbacks: false),
    ]

    static func named(_ id: String) -> ClaudeModel {
        // Haiku 4.5 was replaced by Haiku 5.5; keep that choice rather than resetting it.
        let current = id == "claude-haiku-4-5" ? "claude-haiku-5-5" : id
        return all.first { $0.id == current } ?? all[0]
    }
}

enum AssistError: LocalizedError {
    case microphoneDenied
    case noMicrophone
    case screenRecordingDenied
    case speechUnavailable
    case unsupportedLocale(String)
    case noDisplay
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off for Assist."
        case .noMicrophone: "No microphone found."
        case .screenRecordingDenied: "Allow Assist under Screen & System Audio Recording, then reopen Assist."
        case .speechUnavailable: "On-device transcription isn't available on this Mac."
        case .unsupportedLocale(let id): "On-device transcription doesn't support \(id) yet."
        case .noDisplay: "Couldn't find a display to capture."
        case .imageEncodingFailed: "Couldn't encode the screenshot."
        }
    }

    var noticeAction: Notice.Action? {
        switch self {
        case .microphoneDenied: .microphonePrivacy
        case .screenRecordingDenied: .screenRecordingPrivacy
        case .unsupportedLocale: .languageSettings
        default: nil
        }
    }
}

extension Notice {
    init(_ error: Error) {
        if let error = error as? AssistError {
            self.init(text: error.localizedDescription, action: error.noticeAction)
        } else {
            self.init(text: error.localizedDescription, action: nil)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

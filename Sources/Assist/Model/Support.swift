import AppKit
import AVFoundation
import Security

enum Keychain {
    private static let service = "com.sudhan.assist"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum Permissions {
    static func microphone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Screen recording covers both system-audio capture and screenshots.
    static func requireScreenRecording() throws {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw AssistError.screenRecordingDenied
        }
    }

    @MainActor
    static func open(_ action: Notice.Action) {
        let anchor: String
        switch action {
        case .microphonePrivacy: anchor = "Privacy_Microphone"
        case .screenRecordingPrivacy: anchor = "Privacy_ScreenCapture"
        case .apiKeySettings, .languageSettings: return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum QuestionDetector {
    private static let cues = [
        "tell me about", "walk me through", "talk me through", "can you explain", "could you explain",
        "what do you think", "how would you", "how do you", "what would you", "why did you",
        "give me an example", "describe a time", "explain how", "explain why", "your thoughts on",
        "help me understand", "what's your", "what is your", "how did you",
    ]

    private static let openers: Set<String> = [
        "what", "what's", "how", "how's", "why", "when", "where", "which", "who", "whose",
        "can", "could", "would", "will", "should", "do", "does", "did", "is", "are", "have", "has",
        "describe", "explain",
    ]

    static func isQuestion(_ raw: String) -> Bool {
        let text = raw.lowercased().trimmed
        let words = text.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        guard words.count >= 3 else { return false }
        if text.contains("?") { return true }
        if cues.contains(where: text.contains) { return true }
        return words.count <= 30 && openers.contains(String(words[0]))
    }
}

/// Word-overlap check used to drop the mic's copy of speech that came out of the speakers.
enum EchoFilter {
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    static func overlap(_ a: String, _ b: String) -> Double {
        let wa = words(a)
        guard wa.count >= 3 else { return 0 }
        return Double(wa.intersection(words(b)).count) / Double(wa.count)
    }

    private static func sequence(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Is `mic` a copy of what the other side just said? Either most of its words are in one
    /// of their recent lines, or (because the mic and the call audio get cut into utterances
    /// at different points) half of its word pairs appear, in order, somewhere in their
    /// recent speech taken together. Word pairs keep a genuine reply that merely shares
    /// common words from being mistaken for an echo.
    static func isEcho(_ mic: String, of recent: [String]) -> Bool {
        if recent.contains(where: { overlap(mic, $0) >= 0.6 }) { return true }
        let said = sequence(mic)
        guard said.count >= 4 else { return false }
        let heard = sequence(recent.joined(separator: " "))
        guard heard.count >= 2 else { return false }
        let pairs = Set(zip(heard, heard.dropFirst()).map { $0 + " " + $1 })
        let matched = zip(said, said.dropFirst()).filter { pairs.contains($0 + " " + $1) }.count
        return Double(matched) / Double(said.count - 1) >= 0.5
    }

    /// `mic` with the other side's words taken out, keeping whatever I said myself. One mic
    /// utterance often holds both: their sentence coming out of the speakers, then my reply
    /// before any pause. Dropping the whole line would lose my words, so only runs of three
    /// or more words that follow their recent speech pair by pair are removed. Shorter
    /// matches stay (I may simply have reused a phrase of theirs), and stray misheard words
    /// stuck to a removed run go with it. Returns "" when nothing of mine is left.
    static func withoutEcho(_ mic: String, of recent: [String]) -> String {
        let raw = mic.split(whereSeparator: \.isWhitespace).map(String.init)
        let said = raw.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let heard = sequence(recent.joined(separator: " "))
        guard raw.count >= 2, heard.count >= 2 else { return isEcho(mic, of: recent) ? "" : mic }
        let pairs = Set(zip(heard, heard.dropFirst()).map { $0 + " " + $1 })
        let known = Set(heard)

        var echoed = [Bool](repeating: false, count: raw.count)
        for index in 0..<(raw.count - 1) where pairs.contains(said[index] + " " + said[index + 1]) {
            echoed[index] = true
            echoed[index + 1] = true
        }
        /// Consecutive words with the same flag.
        func runs() -> [Range<Int>] {
            var result: [Range<Int>] = []
            var start = 0
            for index in 1...raw.count where index == raw.count || echoed[index] != echoed[start] {
                result.append(start..<index)
                start = index
            }
            return result
        }
        // A short match is me reusing their phrase, not an echo.
        for run in runs() where echoed[run.lowerBound] && run.count < 3 { run.forEach { echoed[$0] = false } }
        guard echoed.contains(true) else { return isEcho(mic, of: recent) ? "" : mic }
        // Leftovers next to an echo that are too short to be a sentence of mine: a lone word,
        // a fragment caught between two echoes, or one made mostly of their words (misheard echo).
        let pieces = runs()
        for (position, run) in pieces.enumerated() where !echoed[run.lowerBound] && run.count < 3 {
            let between = position > 0 && position < pieces.count - 1
            let theirs = run.filter { known.contains(said[$0]) }.count
            if run.count == 1 || between || theirs * 2 >= run.count { run.forEach { echoed[$0] = true } }
        }
        return raw.indices.filter { !echoed[$0] }.map { raw[$0] }.joined(separator: " ")
    }
}

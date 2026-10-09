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
}

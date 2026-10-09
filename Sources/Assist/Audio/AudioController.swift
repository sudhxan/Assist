import AVFoundation

/// Owns the mic + system-audio captures and routes their buffers to the right transcriber.
final class AudioController: @unchecked Sendable {
    struct StartResult {
        var systemAudio: Bool
        var systemAudioError: Error?
        /// Set when Parakeet was requested but Apple's recognizer had to take over.
        var speechFallback: Error?
        var engine: SpeechEngine
    }

    var onTranscript: (@Sendable (Speaker, LiveTranscriber.Update) -> Void)?
    var onLevel: (@Sendable (Speaker, Float) -> Void)?
    var onDictation: (@Sendable (LiveTranscriber.Update) -> Void)?
    var onStatus: (@Sendable (String?) -> Void)?
    var onSystemAudioStopped: (@Sendable (Error?) -> Void)?

    private let mic = MicCapture()
    private let system = SystemAudioCapture()
    private let lock = NSLock()
    private var micTranscriber: StreamingTranscriber?
    private var systemTranscriber: StreamingTranscriber?
    private var dictation: LiveTranscriber?
    private var micSpeaker: Speaker = .me
    private var micUsers: Set<String> = []

    init() {
        mic.onBuffer = { [weak self] buffer in self?.routeMic(buffer) }
        system.onBuffer = { [weak self] buffer in self?.routeSystem(buffer) }
        system.onStopped = { [weak self] error in self?.onSystemAudioStopped?(error) }
    }

    // MARK: Meeting

    func startMeeting(locale: Locale, includeSystemAudio: Bool, engine requested: SpeechEngine) async throws -> StartResult {
        guard await Permissions.microphone() else { throw AssistError.microphoneDenied }
        onStatus?("Waking up…")

        var engine = requested == .parakeet && ParakeetTranscriber.supports(locale) ? SpeechEngine.parakeet : .apple
        var fallback: Error?
        var systemOK = false
        var systemError: Error?
        if includeSystemAudio {
            do {
                try Permissions.requireScreenRecording()
                let (transcriber, used, error) = try await startTranscriber(engine, locale: locale, speaker: .them)
                engine = used
                fallback = fallback ?? error
                lock.withLock { systemTranscriber = transcriber }
                try await system.start()
                systemOK = true
            } catch {
                systemError = error
                let transcriber = lock.withLock {
                    let t = systemTranscriber
                    systemTranscriber = nil
                    return t
                }
                await transcriber?.stop()
            }
        }

        // Without a separate feed for the other side, the mic is "the room".
        let speaker: Speaker = systemOK ? .me : .room
        do {
            let (transcriber, used, error) = try await startTranscriber(engine, locale: locale, speaker: speaker)
            engine = used
            fallback = fallback ?? error
            lock.withLock {
                micTranscriber = transcriber
                micSpeaker = speaker
            }
            try useMic("meeting")
        } catch {
            await stopMeeting()
            throw error
        }
        return StartResult(systemAudio: systemOK, systemAudioError: systemError, speechFallback: fallback, engine: engine)
    }

    /// Starts the requested recognizer for one channel, falling back to Apple's if Parakeet
    /// can't start (for example, offline before its first download).
    private func startTranscriber(_ engine: SpeechEngine, locale: Locale,
                                  speaker: Speaker) async throws -> (StreamingTranscriber, SpeechEngine, Error?) {
        let onUpdate: @Sendable (LiveTranscriber.Update) -> Void = { [weak self] update in self?.onTranscript?(speaker, update) }
        if engine == .parakeet {
            let parakeet = ParakeetTranscriber(onUpdate: onUpdate)
            do {
                try await parakeet.start(locale: locale, onStatus: onStatus)
                return (parakeet, .parakeet, nil)
            } catch {
                await parakeet.stop()
                let apple = LiveTranscriber(onUpdate: onUpdate)
                try await apple.start(locale: locale, onStatus: onStatus)
                return (apple, .apple, error)
            }
        }
        let apple = LiveTranscriber(onUpdate: onUpdate)
        try await apple.start(locale: locale, onStatus: onStatus)
        return (apple, .apple, nil)
    }

    func stopMeeting() async {
        await system.stop()
        let (micT, systemT) = lock.withLock {
            let parts = (micTranscriber, systemTranscriber)
            micTranscriber = nil
            systemTranscriber = nil
            return parts
        }
        releaseMic("meeting")
        await micT?.stop()
        await systemT?.stop()
    }

    // MARK: Dictation

    func startDictation(locale: Locale) async throws {
        guard await Permissions.microphone() else { throw AssistError.microphoneDenied }
        let transcriber = LiveTranscriber { [weak self] update in self?.onDictation?(update) }
        lock.withLock { dictation = transcriber }
        try useMic("dictation")
        try await transcriber.start(locale: locale)
    }

    func stopDictation() async {
        let transcriber = lock.withLock {
            let t = dictation
            dictation = nil
            return t
        }
        releaseMic("dictation")
        await transcriber?.stop()
    }

    // MARK: Routing (capture threads)

    private func routeMic(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let dictation = dictation
        let meeting = micTranscriber
        let speaker = micSpeaker
        lock.unlock()
        // While you're talking to Assist, keep it out of the meeting transcript.
        if let dictation { dictation.append(buffer) } else { meeting?.append(buffer) }
        onLevel?(speaker, buffer.level)
    }

    private func routeSystem(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let transcriber = systemTranscriber
        lock.unlock()
        transcriber?.append(buffer)
        onLevel?(.them, buffer.level)
    }

    // MARK: Mic sharing

    private func useMic(_ user: String) throws {
        let shouldStart = lock.withLock {
            let wasEmpty = micUsers.isEmpty
            micUsers.insert(user)
            return wasEmpty
        }
        guard shouldStart else { return }
        do {
            try onMain { try self.mic.start() }
        } catch {
            lock.withLock { _ = micUsers.remove(user) }
            throw error
        }
    }

    private func releaseMic(_ user: String) {
        let shouldStop = lock.withLock {
            micUsers.remove(user)
            return micUsers.isEmpty
        }
        if shouldStop { onMain { self.mic.stop() } }
    }

    private func onMain<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }
}

import AVFoundation
import Speech

/// Streams audio buffers into Apple's on-device SpeechAnalyzer and reports
/// volatile (in-progress) and final transcript text.
final class LiveTranscriber: @unchecked Sendable {
    enum Update: Sendable {
        case volatile(String)
        /// The speaker has probably finished (only Parakeet reports this).
        case pause(String)
        case final(String)
        /// Punctuation that belongs at the end of the previous final arrived late.
        case amend(String)
    }

    private let onUpdate: @Sendable (Update) -> Void
    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(onUpdate: @escaping @Sendable (Update) -> Void) {
        self.onUpdate = onUpdate
    }

    func start(locale: Locale, onStatus: (@Sendable (String?) -> Void)? = nil) async throws {
        guard SpeechTranscriber.isAvailable else { throw AssistError.speechUnavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AssistError.unsupportedLocale(locale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: supported,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        // Open the input stream right away so audio that arrives while the model loads is queued, not lost.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        lock.withLock {
            self.targetFormat = format
            self.continuation = continuation
        }

        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            onStatus?("Downloading speech model…")
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let onUpdate = onUpdate
        let results = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    onUpdate(result.isFinal ? .final(text) : .volatile(text))
                }
            } catch {
                // The stream ends with an error when the analyzer is torn down; nothing to report.
            }
        }
        lock.withLock {
            self.analyzer = analyzer
            self.resultsTask = results
        }
        try await analyzer.start(inputSequence: stream)
    }

    /// Called on the capture thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let continuation = continuation
        let format = targetFormat ?? buffer.format
        lock.unlock()
        guard let continuation, let converted = convert(buffer, to: format) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Flushes remaining audio and waits (briefly) for the last final results.
    func stop() async {
        let (continuation, analyzer, results) = lock.withLock {
            let parts = (self.continuation, self.analyzer, self.resultsTask)
            self.continuation = nil
            return parts
        }
        continuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        if let results {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await results.value }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()
                group.cancelAll()
            }
            results.cancel()
        }
    }

    /// Always produces a fresh buffer: tap buffers can be reused once the tap callback returns.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        let fed = FedFlag()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if fed.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed.value = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    private final class FedFlag: @unchecked Sendable {
        var value = false
    }
}

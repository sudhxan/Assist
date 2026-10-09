import AVFoundation
import FluidAudio

/// A streaming speech-to-text engine fed from a capture thread.
protocol StreamingTranscriber: AnyObject, Sendable {
    func start(locale: Locale, onStatus: (@Sendable (String?) -> Void)?) async throws
    /// Called on the capture thread. Must not block.
    func append(_ buffer: AVAudioPCMBuffer)
    func stop() async
}

extension LiveTranscriber: StreamingTranscriber {}

/// English transcription with NVIDIA's Parakeet Unified 0.6B (FastConformer encoder + RNNT
/// decoder) on the Neural Engine, at its lowest-latency streaming tier: 160 ms chunks with
/// 160 ms of look-ahead, 2.4% WER on LibriSpeech test-clean. It runs on the ANE, so it never
/// competes with the on-device LLM for the GPU.
///
/// The model's transcript only grows, so turn boundaries come straight from the stream: a
/// stall in new words while the audio has gone quiet is a pause (the moment Assist starts
/// drafting an answer), and a longer one finalizes the utterance.
final class ParakeetTranscriber: StreamingTranscriber, @unchecked Sendable {
    /// Words have stopped arriving and the audio is quiet: they may be done.
    static let pauseAfter: TimeInterval = 0.3
    /// Quiet long enough to call the utterance finished.
    static let finalAfter: TimeInterval = 0.65

    private let onUpdate: @Sendable (LiveTranscriber.Update) -> Void
    private let lock = NSLock()
    private var pending: [Float] = []
    private var converter: AVAudioConverter?
    private var gate = EnergyGate()
    private var manager: StreamingUnifiedAsrManager?
    private var pump: Task<Void, Never>?
    private var segmenter = UtteranceSegmenter()

    private static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    /// [left, chunk, right] in 80 ms encoder frames: 5.6 s of history, 160 ms chunks, 160 ms look-ahead.
    static let config = UnifiedConfig(leftFrames: 70, chunkFrames: 2, rightFrames: 2)

    init(onUpdate: @escaping @Sendable (LiveTranscriber.Update) -> Void) {
        self.onUpdate = onUpdate
    }

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    static var isDownloaded: Bool {
        let folder = modelsDirectory.appendingPathComponent(Repo.parakeetUnified.folderName)
        let encoder = ModelNames.ParakeetUnified.streamingEncoderFile(precision: .int8, contextSuffix: config.contextSuffix)
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(encoder).path)
    }

    static func supports(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "en"
    }

    func start(locale: Locale, onStatus: (@Sendable (String?) -> Void)?) async throws {
        let manager = StreamingUnifiedAsrManager(config: Self.config, encoderPrecision: .int8)
        if !Self.isDownloaded { onStatus?("Downloading Parakeet speech model…") }
        try await manager.loadModels(to: Self.modelsDirectory, configuration: nil) { progress in
            onStatus?(String(format: "Downloading Parakeet speech model… %.0f%%", progress.fractionCompleted * 100))
        }
        lock.withLock { self.manager = manager }
        pump = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                await self?.drain(final: false)
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let samples = resample(buffer) else { return }
        let db = Self.loudness(samples)
        lock.withLock {
            pending.append(contentsOf: samples)
            gate.feed(db: db, seconds: Double(samples.count) / 16_000, at: Date())
        }
    }

    func stop() async {
        pump?.cancel()
        pump = nil
        await drain(final: true)
        let manager = lock.withLock {
            let m = self.manager
            self.manager = nil
            return m
        }
        await manager?.cleanup()
    }

    /// Feeds buffered audio to the decoder and turns the growing transcript into updates.
    private func drain(final: Bool) async {
        let (manager, samples) = lock.withLock {
            let s = pending
            pending.removeAll(keepingCapacity: true)
            return (self.manager, s)
        }
        guard let manager else { return }
        do {
            if !samples.isEmpty, let buffer = Self.buffer(samples) {
                try await manager.appendAudio(buffer)
                try await manager.processBufferedAudio()
            }
            if final { _ = try await manager.finish() }
        } catch {
            return
        }
        let transcript = await manager.getPartialTranscript()
        let silence = lock.withLock { gate.silence(at: Date()) }
        let updates = lock.withLock { segmenter.update(transcript: transcript, now: Date(), silence: silence, flush: final) }
        updates.forEach(onUpdate)
    }

    // MARK: Audio

    private func resample(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let target = Self.format
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
        }
        guard let converter, buffer.frameLength > 0 else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let data = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    static func loudness(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -120 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return 10 * log10(max(sum / Float(samples.count), 1e-12))
    }
}

/// Energy voice-activity gate with an adaptive noise floor: the floor drops instantly to
/// quieter audio and creeps up at 2 dB/s, so steady room noise stops counting as speech
/// within a few seconds while speech (10 dB above it) always does.
struct EnergyGate {
    private var floor: Float = -70
    private var lastSpeech = Date.distantPast

    mutating func feed(db: Float, seconds: Double, at now: Date) {
        floor = min(db, floor + Float(2 * seconds))
        if db > max(floor + 10, -55) { lastSpeech = now }
    }

    func silence(at now: Date) -> TimeInterval {
        now.timeIntervalSince(lastSpeech)
    }
}

/// Cuts an append-only transcript into utterances: `.volatile` while words arrive, `.pause`
/// once they stop and the audio is quiet, `.final` when the quiet lasts. Long monologues are
/// committed at sentence ends so lines stay readable.
struct UtteranceSegmenter {
    private var committed = 0
    private var lastLength = 0
    private var lastGrowth = Date.distantPast
    private var announcedPause = false

    mutating func update(transcript: String, now: Date, silence: TimeInterval, flush: Bool = false) -> [LiveTranscriber.Update] {
        var updates: [LiveTranscriber.Update] = []
        if transcript.count < committed { committed = 0 } // decoder was reset
        // The decoder places sentence-final punctuation using right context, so it can land
        // after the utterance was already committed. Hand it back to that utterance.
        var tail = String(transcript.dropFirst(committed))
        if committed > 0 {
            let leading = tail.prefix { ".?!,;: ".contains($0) }
            if !leading.isEmpty {
                let marks = leading.filter { !$0.isWhitespace }
                if !marks.isEmpty { updates.append(.amend(String(marks))) }
                committed += leading.count
                tail.removeFirst(leading.count)
            }
        }
        let text = tail.trimmed

        if transcript.count != lastLength {
            lastLength = transcript.count
            lastGrowth = now
            announcedPause = false
            if !text.isEmpty { updates.append(.volatile(text)) }
            // The decoder writes punctuation: a question mark is its own end-of-question call,
            // so treat it as a pause right away instead of waiting for silence.
            if text.hasSuffix("?") {
                announcedPause = true
                updates.append(.pause(text))
            }
        }
        guard !text.isEmpty else { return updates }
        let stalled = now.timeIntervalSince(lastGrowth)

        if flush || (stalled >= 0.35 && silence >= ParakeetTranscriber.finalAfter) || stalled >= 1.6 {
            committed = transcript.count
            updates.append(.final(text))
            return updates
        }
        if !announcedPause, stalled >= 0.15, silence >= ParakeetTranscriber.pauseAfter {
            announcedPause = true
            updates.append(.pause(text))
        }
        // A long run-on turn: commit through the last finished sentence.
        if text.split(separator: " ").count > 45, let cut = Self.lastSentenceEnd(in: tail, minimumWords: 20) {
            let sentence = String(tail[..<cut]).trimmed
            committed += tail.distance(from: tail.startIndex, to: cut)
            updates.append(.final(sentence))
        }
        return updates
    }

    private static func lastSentenceEnd(in text: String, minimumWords: Int) -> String.Index? {
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            if ".?!".contains(text[previous]), index < text.endIndex, text[index] == " " {
                let words = text[..<index].split(separator: " ").count
                return words >= minimumWords ? index : nil
            }
            index = previous
        }
        return nil
    }
}

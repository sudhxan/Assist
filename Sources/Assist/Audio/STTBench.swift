import AVFoundation
import Foundation

/// `Assist --bench-stt`: streams synthesized meeting speech in real time through Parakeet and
/// Apple's SpeechAnalyzer side by side, then reports accuracy (WER) and how long after each
/// utterance ends each engine reports a pause and a final transcript.
enum STTBench {
    static let utterances = [
        "Thanks for joining today. Before we dive in, can you tell me about the biggest migration you have led?",
        "We are thinking about moving our scheduling service to Kubernetes next quarter.",
        "How would you handle on call for a team of thirty engineers?",
        "Walk me through how you would design the backfill for eight years of hospital records.",
    ]

    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var events: [(time: TimeInterval, kind: String, text: String)] = []
        let start: Date
        init(start: Date) { self.start = start }
        func record(_ update: LiveTranscriber.Update) {
            let t = Date().timeIntervalSince(start)
            lock.withLock {
                switch update {
                case .volatile: break
                case .amend(let marks): if let last = events.lastIndex(where: { $0.kind == "final" }) { events[last].text += marks }
                case .pause(let text): events.append((t, "pause", text))
                case .final(let text): events.append((t, "final", text))
                }
            }
        }
    }

    static func run() async {
        print("\n== Speech recognition (real-time stream, \(utterances.count) utterances)")
        guard let (samples, ends) = synthesize() else { print("  ✗ couldn't synthesize speech with `say`"); return }
        print(String(format: "audio: %.1f s", Double(samples.count) / 16_000))

        let start = Date()
        let parakeetLog = Recorder(start: start)
        let appleLog = Recorder(start: start)
        let parakeet = ParakeetTranscriber { parakeetLog.record($0) }
        let apple = LiveTranscriber { appleLog.record($0) }
        do {
            let loadStart = Date()
            try await parakeet.start(locale: Locale(identifier: "en-US")) { status in
                if let status { print("  \(status)") }
            }
            print(String(format: "Parakeet loaded in %.2f s", Date().timeIntervalSince(loadStart)))
        } catch {
            print("  ✗ Parakeet: \(error.localizedDescription)")
            return
        }
        var appleReady = true
        do { try await apple.start(locale: Locale(identifier: "en-US")) } catch {
            appleReady = false
            print("  (Apple SpeechAnalyzer unavailable here: \(error.localizedDescription))")
        }

        // Stream in 20 ms buffers at real-time pace, so latencies are what a live call sees.
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let clockStart = Date()
        parakeetLog.lock.withLock { parakeetLog.events.removeAll() }
        let streamStart = Date()
        var offset = 0
        while offset < samples.count {
            let count = min(320, samples.count - offset)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress! + offset, count: count) }
            parakeet.append(buffer)
            if appleReady { apple.append(buffer) }
            offset += count
            let due = Double(offset) / 16_000
            let wait = due - Date().timeIntervalSince(clockStart)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
        try? await Task.sleep(for: .seconds(1.5))
        await parakeet.stop()
        if appleReady { await apple.stop() }

        let offsetFromRecorder = streamStart.timeIntervalSince(start)
        report("Parakeet Unified 0.6B (320 ms)", parakeetLog, ends: ends, offset: offsetFromRecorder)
        if appleReady { report("Apple SpeechAnalyzer", appleLog, ends: ends, offset: offsetFromRecorder) }
    }

    private static func report(_ name: String, _ log: Recorder, ends: [TimeInterval], offset: TimeInterval) {
        let events = log.lock.withLock { log.events }
        let finals = events.filter { $0.kind == "final" }
        let hypothesis = finals.map(\.text).joined(separator: " ")
        let wer = wordErrorRate(reference: utterances.joined(separator: " "), hypothesis: hypothesis)
        var pauseLags: [Double] = []
        var finalLags: [Double] = []
        for (index, end) in ends.enumerated() {
            let windowStart = index == 0 ? 0 : ends[index - 1] + 0.2
            let next = index + 1 < ends.count ? ends[index + 1] : .infinity
            let inWindow = events.filter { $0.time - offset > windowStart && $0.time - offset < next }
            // The pause that ends the turn is the last one before its final; earlier ones are
            // breaths between sentences.
            guard let final = inWindow.first(where: { $0.kind == "final" && $0.time - offset >= end - 0.1 }) else { continue }
            finalLags.append(final.time - offset - end)
            if let pause = inWindow.last(where: { $0.kind == "pause" && $0.time <= final.time && $0.time - offset >= end - 0.1 }) {
                pauseLags.append(pause.time - offset - end)
            }
        }
        func describe(_ lags: [Double]) -> String {
            guard !lags.isEmpty else { return "—" }
            return String(format: "median %.0f ms (max %.0f)", median(lags) * 1000, (lags.max() ?? 0) * 1000)
        }
        print("\n\(name): WER \(String(format: "%.1f", wer * 100))%")
        print("  pause after end of speech: \(describe(pauseLags))")
        print("  final after end of speech: \(describe(finalLags))")
        for final in finals { print("  ┆ \(final.text)") }
    }

    /// Renders each utterance with macOS `say`, then joins them with 1.6 s gaps.
    private static func synthesize() -> ([Float], [TimeInterval])? {
        var samples = [Float](repeating: 0, count: 8_000)
        var ends: [TimeInterval] = []
        let directory = FileManager.default.temporaryDirectory
        for (index, text) in utterances.enumerated() {
            let url = directory.appendingPathComponent("assist-stt-\(index).wav")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "--data-format=LEF32@16000", text]
            guard (try? say.run()) != nil else { return nil }
            say.waitUntilExit()
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData?[0] else { return nil }
            var speech = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
            // Trim `say`'s trailing silence so "end of speech" is the last audible sample.
            while let last = speech.last, abs(last) < 0.004 { speech.removeLast() }
            samples += speech
            ends.append(Double(samples.count) / 16_000)
            samples += [Float](repeating: 0, count: 25_600)
        }
        return (samples, ends)
    }

    static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        func words(_ s: String) -> [String] {
            s.lowercased().replacingOccurrences(of: "-", with: " ")
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        }
        let r = words(reference), h = words(hypothesis)
        guard !r.isEmpty else { return 0 }
        var previous = Array(0...h.count)
        for i in 1...r.count {
            var current = [i] + [Int](repeating: 0, count: h.count)
            for j in stride(from: 1, through: h.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[h.count]) / Double(r.count)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

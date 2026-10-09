import Accelerate
import AppKit
import AVFoundation
import ScreenCaptureKit
import Vision

/// Microphone input via AVAudioEngine.
final class MicCapture: @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?

    func start() throws {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AssistError.noMicrophone }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine

        // Plugging in headphones / switching mics invalidates the engine; rebuild it.
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.stop()
            try? self.start()
        }
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}

/// Everything the Mac is playing (the other people on the call), via ScreenCaptureKit.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStopped: ((Error?) -> Void)?

    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "assist.system-audio", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "assist.system-video", qos: .utility)

    func start() async throws {
        try Permissions.requireScreenRecording()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw AssistError.noDisplay }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // Video is required by the API but unused: keep it tiny and slow.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let pcm = sampleBuffer.makePCMBuffer() else { return }
        onBuffer?(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        onStopped?(error)
    }
}

enum ScreenGrabber {
    /// Screenshot of one display (Assist's own windows excluded) as JPEG, downscaled for cloud models.
    static func capture(displayID: CGDirectDisplayID?) async throws -> Data {
        let image = try await captureImage(displayID: displayID, maxDimension: 1800)
        guard let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw AssistError.imageEncodingFailed
        }
        return jpeg
    }

    /// Screenshot of one display (Assist's own windows excluded), at most `maxDimension` pixels on its long side.
    static func captureImage(displayID: CGDirectDisplayID?, maxDimension: CGFloat) async throws -> CGImage {
        try Permissions.requireScreenRecording()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw AssistError.noDisplay
        }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        var width = CGFloat(display.width) * scale
        var height = CGFloat(display.height) * scale
        let shrink = min(1, maxDimension / max(width, height))
        width *= shrink
        height *= shrink
        config.width = Int(width)
        config.height = Int(height)
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// On-device OCR (Vision, on the Neural Engine). The local model reads the screen as text,
/// which keeps it on the warm, cached text path instead of a cold vision-encoder prefill.
enum ScreenText {
    static func recognize(_ image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        // Vision reports normalized boxes with the origin at the bottom left; read top to bottom.
        return observations
            .sorted { lhs, rhs in
                let dy = lhs.boundingBox.origin.y - rhs.boundingBox.origin.y
                return abs(dy) > 0.008 ? dy > 0 : lhs.boundingBox.origin.x < rhs.boundingBox.origin.x
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

extension CMSampleBuffer {
    func makePCMBuffer() -> AVAudioPCMBuffer? {
        guard let description = formatDescription,
              var asbd = description.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(self, at: 0, frameCount: Int32(frames),
                                                                   into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}

extension AVAudioPCMBuffer {
    /// 0…1 loudness, mapped from roughly -55 dB…-10 dB.
    var level: Float {
        guard frameLength > 0, let channel = floatChannelData?[0] else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(frameLength))
        let db = 10 * log10(max(meanSquare, 1e-12))
        return min(1, max(0, (db + 55) / 45))
    }
}

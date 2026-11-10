import Accelerate
import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage.CIFilterBuiltins
import Vision

/// Microphone input via AVAudioEngine.
final class MicCapture: @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Ask macOS to subtract whatever the Mac is playing from the mic signal (Apple's voice
    /// processing: acoustic echo cancellation against the output device). Takes effect at the
    /// next `start()`. Without headphones this is what keeps the other side's voice out of
    /// your half of the transcript.
    var echoCancellation = false
    /// Whether the running engine is actually cancelling echo.
    private(set) var isCancellingEcho = false
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private let lock = NSLock()
    private var buffersSeen = 0
    private var generation = 0
    private var restarts: [Date] = []

    func start() throws {
        guard engine == nil else { return }
        if echoCancellation {
            do {
                try start(cancellingEcho: true)
                watchForSilence()
                return
            } catch {
                teardown() // voice processing isn't available on this input; use the plain mic
            }
        }
        try start(cancellingEcho: false)
    }

    private func start(cancellingEcho: Bool) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if cancellingEcho {
            try input.setVoiceProcessingEnabled(true)
            // Voice processing turns other audio down by default. The call must stay as loud as it was.
            input.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AssistError.noMicrophone }

        lock.withLock { buffersSeen = 0; generation += 1 }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.withLock { self.buffersSeen += 1 }
            // Voice processing can deliver several channels; the processed voice is the first.
            self.onBuffer?(buffer.format.channelCount > 1 ? (buffer.firstChannel() ?? buffer) : buffer)
        }
        self.engine = engine
        engine.prepare()
        do { try engine.start() } catch {
            teardown()
            throw error
        }
        isCancellingEcho = cancellingEcho

        // Plugging in headphones / switching mics stops the engine; rebuild it. Turning voice
        // processing on or off reconfigures the device too, so a burst of these right after
        // a start means it isn't settling: drop to the plain mic rather than loop.
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            self.restarts = self.restarts.filter { now.timeIntervalSince($0) < 5 } + [now]
            let cancel = self.isCancellingEcho && self.restarts.count <= 3
            self.teardown()
            if (try? self.start(cancellingEcho: cancel)) == nil, cancel { try? self.start(cancellingEcho: false) }
        }
    }

    /// Voice processing can start cleanly and still deliver nothing on some audio devices. A
    /// transcript with no "You" is worse than one with echo, so fall back to the plain mic.
    private func watchForSilence() {
        let started = lock.withLock { generation }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.engine != nil, self.isCancellingEcho else { return }
            let (seen, current) = self.lock.withLock { (self.buffersSeen, self.generation) }
            guard current == started, seen == 0 else { return }
            self.teardown()
            try? self.start(cancellingEcho: false)
        }
    }

    func stop() {
        teardown()
    }

    private func teardown() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isCancellingEcho = false
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
    /// Long side of the image the on-device path reads with OCR. High enough to keep a Retina
    /// laptop screen at native resolution, where small code fonts read most reliably.
    static let ocrMaxDimension: CGFloat = 4096
    /// Long side of the screenshot sent to cloud models: Claude's high-resolution vision limit
    /// (2576 px). Larger images are only downscaled again by the provider.
    static let cloudMaxDimension: CGFloat = 2576

    /// `image` shrunk to at most `maxDimension` pixels on its long side.
    static func scaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let shrink = min(1, maxDimension / CGFloat(max(image.width, image.height)))
        guard shrink < 1 else { return image }
        let width = Int(CGFloat(image.width) * shrink), height = Int(CGFloat(image.height) * shrink)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// `image` as a JPEG for a cloud model, at most `cloudMaxDimension` on its long side.
    static func jpeg(_ image: CGImage) throws -> Data {
        let sized = scaled(image, maxDimension: cloudMaxDimension)
        guard let jpeg = NSBitmapImageRep(cgImage: sized).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw AssistError.imageEncodingFailed
        }
        return jpeg
    }

    /// Screenshot of one display (Assist's own windows excluded), at most `maxDimension` pixels on its long side.
    static func captureImage(displayID: CGDirectDisplayID?, maxDimension: CGFloat = ocrMaxDimension) async throws -> CGImage {
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

/// On-device OCR (Vision, on the Neural Engine), laid out by `ScreenLayout` so panes stay
/// apart and code keeps its indentation. The on-device model reads the screen as this text,
/// which keeps it on the warm, cached text path instead of a cold vision-encoder prefill.
enum ScreenText {
    /// Reads the screen twice, as captured and as inverted grayscale, and keeps the better
    /// reading of each region. Vision reads dark text on a light background best: on a
    /// dark-theme editor it drops syntax-colored keywords and parameters (`def`, `k: int`)
    /// that it reads cleanly once inverted, yet each pass also misses lines the other gets.
    /// The two passes run concurrently on the Neural Engine.
    static func recognize(_ image: CGImage) async throws -> String {
        async let direct = lines(in: image)
        async let flipped = lines(in: inverted(image))
        return ScreenLayout.render(ScreenLayout.merge(try await direct, try await flipped))
    }

    private static func lines(in image: CGImage) async throws -> [OCRLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction rewrites what looks like a misspelling, and code is full of
        // them: identifiers, operators, l/1 and O/0. The model fixes stray prose typos itself.
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image)
        let size = CGSize(width: image.width, height: image.height)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            return OCRLine(box: box, items: pieces(of: text, box: box, size: size))
        }
    }

    private static let imaging = CIContext(options: [.cacheIntermediates: false])

    private static func inverted(_ image: CGImage) -> CGImage {
        let gray = CIFilter.colorControls()
        gray.inputImage = CIImage(cgImage: image)
        gray.saturation = 0
        let invert = CIFilter.colorInvert()
        invert.inputImage = gray.outputImage
        guard let output = invert.outputImage else { return image }
        return imaging.createCGImage(output, from: output.extent) ?? image
    }

    /// Splits a leading line number ("12  return x") off its line, using Vision's box for each
    /// part, so an editor's gutter can be dropped while the code keeps its real position.
    private static func pieces(of text: RecognizedText, box: CGRect, size: CGSize) -> [OCRItem] {
        let string = text.string
        let whole = OCRItem(text: string, box: box)
        guard let match = string.prefixMatch(of: #/\d{1,4}\s+/#), match.range.upperBound < string.endIndex,
              let numberBox = text.boundingBox(for: string.startIndex..<string.index(before: match.range.upperBound)),
              let restBox = text.boundingBox(for: match.range.upperBound..<string.endIndex) else { return [whole] }
        return [
            OCRItem(text: String(string[..<match.range.upperBound]).trimmingCharacters(in: .whitespaces),
                    box: numberBox.boundingBox.toImageCoordinates(size, origin: .upperLeft)),
            OCRItem(text: String(string[match.range.upperBound...]),
                    box: restBox.boundingBox.toImageCoordinates(size, origin: .upperLeft)),
        ]
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
    /// A mono copy of the first channel (float buffers only).
    func firstChannel() -> AVAudioPCMBuffer? {
        guard let source = floatChannelData?[0],
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false),
              let copy = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frameLength), let target = copy.floatChannelData?[0] else { return nil }
        copy.frameLength = frameLength
        // Interleaved buffers keep every channel in one plane, `stride` samples apart.
        let step = format.isInterleaved ? Int(format.channelCount) : 1
        for frame in 0..<Int(frameLength) { target[frame] = source[frame * step] }
        return copy
    }

    /// 0…1 loudness, mapped from roughly -55 dB…-10 dB.
    var level: Float {
        guard frameLength > 0, let channel = floatChannelData?[0] else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(frameLength))
        let db = 10 * log10(max(meanSquare, 1e-12))
        return min(1, max(0, (db + 55) / 45))
    }
}

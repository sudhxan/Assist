import CoreGraphics
import Foundation
import ImageIO

/// `Assist --bench-screen=<dir> [--model=<model-id>] [--think=<tokens>] [--only=a,b] [--out=<dir>]`: runs every PNG in `<dir>`
/// through the on-device Screen path exactly as the app does (OCR → prompt → answer) and
/// writes `<name>.ocr.txt`, `<name>.answer.md` and a timing line per screenshot to `--out`.
enum ScreenBench {
    static func run(_ arguments: [String]) async {
        guard let dir = value("--bench-screen=", in: arguments) else { return }
        let out = URL(fileURLWithPath: value("--out=", in: arguments) ?? dir)
        let spec = value("--model=", in: arguments).map(LocalModelSpec.named) ?? LocalModelSpec.recommended
        let only = value("--only=", in: arguments).map { Set($0.split(separator: ",").map(String.init)) }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".png") }.sorted()
            .filter { only?.contains(($0 as NSString).deletingPathExtension) ?? true }
        print("\n== Screen path · \(spec.label) · \(files.count) screenshots")
        let engine = LocalEngine.shared
        do { try await engine.load(spec) } catch { print("  ✗ \(error.localizedDescription)"); return }

        for file in files {
            let name = (file as NSString).deletingPathExtension
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent(file) as CFURL, nil),
                  let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("  ✗ \(file): unreadable"); continue }
            do {
                let image = ScreenGrabber.scaled(full, maxDimension: ScreenGrabber.ocrMaxDimension)
                var clock = Date()
                let text = try await ScreenText.recognize(image)
                let ocrSeconds = Date().timeIntervalSince(clock)
                try text.write(to: out.appendingPathComponent("\(name).ocr.txt"), atomically: true, encoding: .utf8)

                let request = LocalScreenRequest(ocrText: text, typed: "", context: PromptContext(profile: "", prerequisites: "", notes: "", meeting: ""))
                var budget = request.budget
                if let think = value("--think=", in: arguments).flatMap(Int.init) { budget.thinking = think }
                clock = Date()
                let collector = AnswerCollector()
                try await engine.generate(request.prompt, id: UUID(), continuing: nil, budget: budget) { event in
                    collector.apply(event)
                }
                let seconds = Date().timeIntervalSince(clock)
                try collector.text.write(to: out.appendingPathComponent("\(name).answer.md"), atomically: true, encoding: .utf8)
                print(String(format: "%@ · OCR %.2f s (%d chars) · answer %.1f s · %d thinking tokens · %@", name, ocrSeconds, text.count,
                             seconds, collector.stats?.thinkingTokens ?? 0, collector.stats?.summary ?? ""))
            } catch {
                print("  ✗ \(name): \(error.localizedDescription)")
            }
        }
    }

    private static func value(_ prefix: String, in arguments: [String]) -> String? {
        arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}

private final class AnswerCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var finished: LocalStats?

    var text: String { lock.withLock { buffer } }
    var stats: LocalStats? { lock.withLock { finished } }

    func apply(_ event: LocalEvent) {
        lock.withLock {
            switch event {
            case .replace(let text): buffer = text
            case .delta(let text): buffer += text
            case .thinking: break
            case .finished(let stats): finished = stats
            }
        }
    }
}

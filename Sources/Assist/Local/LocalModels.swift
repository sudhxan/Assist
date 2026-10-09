import Foundation

/// An on-device model Assist can run, plus the optional multi-token-prediction head
/// that lets it draft several tokens per forward pass.
struct LocalModelSpec: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let repo: String
    let mtpRepo: String?
    let downloadGB: Double
    /// Unified memory the model itself wants. `recommended` also leaves 8 GB for the meeting app.
    let recommendedMemoryGB: Int
    let blurb: String

    static let all: [LocalModelSpec] = [
        LocalModelSpec(id: "qwen3.5-9b", label: "Qwen3.5 9B",
                       repo: "mlx-community/Qwen3.5-9B-MLX-4bit", mtpRepo: "mlx-community/Qwen3.5-9B-MTP-4bit",
                       downloadGB: 6.1, recommendedMemoryGB: 16,
                       blurb: "Best on-device answers. Strongest model under 10B."),
        LocalModelSpec(id: "qwen3.5-4b", label: "Qwen3.5 4B",
                       repo: "mlx-community/Qwen3.5-4B-MLX-4bit", mtpRepo: "mlx-community/Qwen3.5-4B-MTP-4bit",
                       downloadGB: 3.2, recommendedMemoryGB: 8,
                       blurb: "Fastest. Half the memory, a step down in depth."),
    ]

    static func named(_ id: String) -> LocalModelSpec {
        all.first { $0.id == id } ?? recommended
    }

    /// The best model that leaves room for a meeting app on this Mac.
    static var recommended: LocalModelSpec {
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory >> 30)
        return all.first { memoryGB >= $0.recommendedMemoryGB + 8 } ?? all[all.count - 1]
    }

    var directory: URL { LocalModelStore.directory(for: repo) }
    var mtpDirectory: URL? { mtpRepo.map(LocalModelStore.directory(for:)) }

    var isDownloaded: Bool {
        LocalModelStore.isComplete(repo) && (mtpRepo.map(LocalModelStore.isComplete) ?? true)
    }
}

/// Model files live in ~/Library/Application Support/Assist/Models/<org>--<name>/.
enum LocalModelStore {
    static let root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Assist/Models", isDirectory: true)

    static func directory(for repo: String) -> URL {
        root.appendingPathComponent(repo.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    private static let completeMarker = ".assist-complete"

    static func isComplete(_ repo: String) -> Bool {
        let dir = directory(for: repo)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent(completeMarker).path) { return true }
        // Folders fetched with `hf download` have no marker; accept them if the weights are all there.
        guard let index = try? Data(contentsOf: dir.appendingPathComponent("model.safetensors.index.json")),
              let object = try? JSONSerialization.jsonObject(with: index) as? [String: Any],
              let map = object["weight_map"] as? [String: String] else {
            return fm.fileExists(atPath: dir.appendingPathComponent("model.safetensors").path)
                && fm.fileExists(atPath: dir.appendingPathComponent("config.json").path)
        }
        return Set(map.values).allSatisfy { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
            && fm.fileExists(atPath: dir.appendingPathComponent("config.json").path)
    }

    static func markComplete(_ repo: String) {
        FileManager.default.createFile(atPath: directory(for: repo).appendingPathComponent(completeMarker).path, contents: Data())
    }

    static func delete(_ spec: LocalModelSpec) {
        try? FileManager.default.removeItem(at: spec.directory)
        if let mtp = spec.mtpDirectory { try? FileManager.default.removeItem(at: mtp) }
    }
}

/// Fetches a Hugging Face repo file by file, skipping files that are already complete,
/// and reports byte-accurate progress across the whole download.
enum ModelDownloader {
    private struct RemoteFile: Decodable {
        let type: String
        let path: String
        let size: Int?
    }

    static func download(_ spec: LocalModelSpec, progress: @escaping @Sendable (Double) -> Void) async throws {
        let repos = [spec.repo] + (spec.mtpRepo.map { [$0] } ?? [])
        var plan: [(repo: String, file: RemoteFile)] = []
        for repo in repos where !LocalModelStore.isComplete(repo) {
            plan += try await listFiles(repo).map { (repo, $0) }
        }
        let total = max(1, plan.reduce(0) { $0 + ($1.file.size ?? 0) })
        var finished = 0
        for (repo, file) in plan {
            try Task.checkCancellation()
            let destination = LocalModelStore.directory(for: repo).appendingPathComponent(file.path)
            let expected = file.size ?? -1
            if let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int, size == expected {
                finished += expected
                progress(Double(finished) / Double(total))
                continue
            }
            let base = finished
            try await fetch(repo: repo, path: file.path, to: destination) { bytes in
                progress(Double(base + bytes) / Double(total))
            }
            finished += max(expected, 0)
        }
        for repo in repos { LocalModelStore.markComplete(repo) }
        progress(1)
    }

    private static func listFiles(_ repo: String) async throws -> [RemoteFile] {
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LLMError.api("Couldn't list \(repo) on Hugging Face.")
        }
        return try JSONDecoder().decode([RemoteFile].self, from: data)
            .filter { $0.type == "file" && !$0.path.hasPrefix(".") && $0.path != "README.md" }
    }

    private static func fetch(repo: String, path: String, to destination: URL, onBytes: @escaping @Sendable (Int) -> Void) async throws {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(encoded)")!
        let delegate = ProgressDelegate(onBytes: onBytes)
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LLMError.api("Download of \(path) failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let onBytes: @Sendable (Int) -> Void
        init(onBytes: @escaping @Sendable (Int) -> Void) { self.onBytes = onBytes }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            onBytes(Int(totalBytesWritten))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}

/// Lets a download report progress at most every half percent, so the UI isn't flooded.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0

    func shouldReport(_ fraction: Double) -> Bool {
        lock.withLock {
            guard fraction - last >= 0.005 || fraction >= 1 else { return false }
            last = fraction
            return true
        }
    }
}

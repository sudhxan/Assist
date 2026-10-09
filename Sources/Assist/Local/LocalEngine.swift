import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// A settled transcript line the engine keeps in its warm KV cache.
struct PrefixLine: Equatable, Sendable {
    let key: UUID
    let text: String
}

/// A request for the on-device model, split by how often each part changes.
struct LocalPrompt: Sendable {
    /// Instructions and the user's context. Changing it rebuilds the warm cache.
    var system: String
    /// Settled transcript lines, oldest first. These stay prefilled between requests.
    var settled: [PrefixLine]
    /// Everything after them: lines that may still change, recent replies, the task.
    /// This is the only part prefilled per request.
    var tail: String
}

struct LocalStats: Sendable {
    /// Time the request waited for the engine (another answer was still generating).
    var queuedSeconds = 0.0
    /// Time spent folding newly settled lines into the warm prefix before this request.
    var syncSeconds = 0.0
    var reusedTokens = 0
    var prefillTokens = 0
    var carriedTokens = 0
    var generatedTokens = 0
    var firstTokenSeconds = 0.0
    var tokensPerSecond = 0.0
    var draftAcceptance: Double?

    var summary: String {
        var parts = [String(format: "%.0f ms to first word", firstTokenSeconds * 1000)]
        if tokensPerSecond > 0 { parts.append(String(format: "%.0f tok/s", tokensPerSecond)) }
        if carriedTokens > 0 { parts.append("\(carriedTokens) tokens pre-written") }
        return parts.joined(separator: " · ")
    }
}

enum LocalEvent: Sendable {
    /// The whole answer so far, replacing what was shown (a verified draft).
    case replace(String)
    case delta(String)
    case finished(LocalStats)
}

enum LocalEngineError: LocalizedError {
    case notDownloaded(String)
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .notDownloaded(let name): "\(name) isn't downloaded yet. Get it in Settings → AI model."
        case .notLoaded: "The on-device model isn't loaded."
        }
    }
}

/// Cancellation and priority flags that callers set without waiting for the engine.
final class EngineSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled: Set<UUID> = []
    private var waiting = 0

    func cancel(_ id: UUID) { lock.withLock { _ = cancelled.insert(id) } }
    func isCancelled(_ id: UUID) -> Bool { lock.withLock { cancelled.contains(id) } }
    func forget(_ id: UUID) { lock.withLock { _ = cancelled.remove(id) } }

    /// An answer is queued: background prefill should get out of the way.
    var answerWaiting: Bool { lock.withLock { waiting > 0 } }
    func enter() { lock.withLock { waiting += 1 } }
    func leave() { lock.withLock { waiting = max(0, waiting - 1) } }
}

/// The on-device model. Every MLX call runs on one serial queue, so the GPU sees one
/// request at a time and nothing races the KV caches.
///
/// Latency comes from four techniques:
/// - **Warm prefix.** The system prompt and settled transcript live in a KV cache that's
///   extended in the background as people talk (append-mode streaming prefill), so a request
///   only prefills the last few lines plus the task.
/// - **Fork, don't rewind.** Qwen3.5's linear-attention layers carry recurrent state that
///   can't be trimmed, so each request runs on a copy of the warm cache. MLX arrays are
///   copy-on-write, so a fork costs well under a millisecond.
/// - **MTP self-speculation.** Qwen3.5's multi-token-prediction head drafts tokens that the
///   main model verifies in one pass (exact greedy output, fewer passes).
/// - **Input-time speculation (PredGen).** `generate(continuing:)` can re-score a draft
///   started before someone finished talking and keep the agreeing prefix. `--bench`
///   measures it; the app regenerates instead, which is faster on this model.
actor LocalEngine {
    static let shared = LocalEngine()

    nonisolated let signals = EngineSignals()
    private let queue = DispatchSerialQueue(label: "com.sudhan.assist.mlx", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private struct Warm {
        var system: String
        var lines: [PrefixLine]
        var tokenCount: Int
        var cache: [KVCache]
    }

    private(set) var loadedID: String?
    private var context: ModelContext?
    private var drafter: (any MTPDrafterModel)?
    private var stopTokens: Set<Int> = []
    private var warm: Warm?
    /// A replacement warm cache being built in the background while `warm` keeps serving.
    private var building: Warm?
    private var lineTokens: [UUID: (text: String, tokens: [Int])] = [:]
    private var outputs: [UUID: [Int]] = [:]
    private var outputOrder: [UUID] = []
    private var registeredMTP = false

    /// When the warm transcript grows past this, it's rebuilt from the newest lines.
    private let maxWarmTokens = 9_000
    private let rebuiltWarmTokens = 5_000
    private let prefillStep = 512
    /// MTP block: 1 verified + 2 drafted tokens per round (the checkpoint's own `block_size`).
    private let mtpBlockSize = 3

    // MARK: Loading

    func load(_ spec: LocalModelSpec) async throws {
        if loadedID == spec.id, context != nil { return }
        unload()
        guard LocalModelStore.isComplete(spec.repo) else { throw LocalEngineError.notDownloaded(spec.label) }

        // Freed MLX buffers are kept for reuse; cap that pool so a meeting app keeps its RAM.
        Memory.cacheLimit = 512 << 20

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let context = try await LLMModelFactory.shared.load(from: spec.directory, using: tokenizerLoader)
        var drafter: (any MTPDrafterModel)?
        if let mtpRepo = spec.mtpRepo, LocalModelStore.isComplete(mtpRepo), let directory = spec.mtpDirectory {
            if !registeredMTP {
                await Qwen35TextMTPRegistration.register()
                registeredMTP = true
            }
            do {
                try Self.rekeyStandaloneMTP(in: directory)
                drafter = try await MTPDrafterModelFactory.shared.load(from: directory, using: tokenizerLoader).model
            } catch {
                NSLog("Assist: MTP head failed to load, decoding without it: \(error)")
            }
        }

        var stops = context.configuration.eosTokenIds
        if let eos = context.tokenizer.eosTokenId { stops.insert(eos) }
        for name in ["<|im_end|>", "<|endoftext|>"] {
            if let id = context.tokenizer.convertTokenToId(name) { stops.insert(id) }
        }

        self.context = context
        self.drafter = drafter
        self.stopTokens = stops
        self.loadedID = spec.id
        warmUp()
    }

    /// mlx-community's standalone MTP heads store bare tensor names (`fc.weight`), while this
    /// release of mlx-swift-lm loads them from under `mtp.`. Re-key the file once, in place.
    private static func rekeyStandaloneMTP(in directory: URL) throws {
        let file = directory.appendingPathComponent("model.safetensors")
        let (arrays, metadata) = try loadArraysAndMetadata(url: file)
        guard !arrays.keys.contains(where: { $0.hasPrefix("mtp.") }) else { return }
        let rekeyed = Dictionary(uniqueKeysWithValues: arrays.map { ("mtp." + $0.key, $0.value) })
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("assist-mtp-\(UUID().uuidString).safetensors")
        try save(arrays: rekeyed, metadata: metadata, url: staging)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: staging)

        let index = directory.appendingPathComponent("model.safetensors.index.json")
        if let data = try? Data(contentsOf: index),
           var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let map = object["weight_map"] as? [String: String] {
            object["weight_map"] = Dictionary(uniqueKeysWithValues: map.map { ("mtp." + $0.key, $0.value) })
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]).write(to: index)
        }
    }

    func unload() {
        context = nil
        drafter = nil
        warm = nil
        building = nil
        lineTokens.removeAll()
        outputs.removeAll()
        outputOrder.removeAll()
        loadedID = nil
        Memory.clearCache()
    }

    /// Compiles the Metal kernels for every shape the hot path uses, so the first real
    /// answer doesn't pay for it.
    private func warmUp() {
        let prompt = LocalPrompt(system: "You are a helpful assistant.", settled: [], tail: "Say OK.")
        _ = try? generate(prompt, id: UUID(), continuing: nil, maxTokens: 4) { _ in }
        warm = nil
    }

    var usesMTP: Bool { drafter != nil && mtpEnabled }

    /// Benchmark hooks.
    private var mtpEnabled = true
    func setMTP(_ enabled: Bool) { mtpEnabled = enabled }
    func resetWarm() {
        warm = nil
        building = nil
    }

    // MARK: Warm prefix

    /// Extends (or rebuilds) the warm cache to cover `settled`. In the background it stops
    /// between chunks as soon as an answer is waiting, keeping whatever it finished.
    func sync(system: String, settled: [PrefixLine], background: Bool) {
        guard context != nil else { return }
        let target = fitted(settled)

        if var current = warm, current.system == system, target.starts(with: current.lines) {
            building = nil
            _ = extend(&current, to: target, background: background)
            warm = current
            return
        }

        // The cached prefix no longer matches (context edited, or the transcript was trimmed):
        // build a replacement while the old cache keeps serving.
        if building == nil || building?.system != system || !target.starts(with: building!.lines) {
            guard let fresh = makeRoot(system: system) else { return }
            building = fresh
        }
        guard var next = building else { return }
        let complete = extend(&next, to: target, background: background)
        building = next
        if complete {
            warm = next
            building = nil
        }
    }

    /// Prefills the lines of `target` that `warm` is missing, batched into chunks of whole
    /// lines so the GPU gets large matmuls and the ledger always matches the cache exactly.
    /// Returns true when it got them all.
    private func extend(_ warm: inout Warm, to target: [PrefixLine], background: Bool) -> Bool {
        var pending = target.dropFirst(warm.lines.count)[...]
        while !pending.isEmpty {
            if background && signals.answerWaiting { return false }
            var batch: [PrefixLine] = []
            var tokens: [Int] = []
            while let line = pending.first, batch.isEmpty || tokens.count + self.tokens(for: line).count <= prefillStep {
                tokens += self.tokens(for: line)
                batch.append(line)
                pending = pending.dropFirst()
            }
            prefill(tokens, into: warm.cache)
            warm.lines += batch
            warm.tokenCount += tokens.count
        }
        return true
    }

    private func makeRoot(system: String) -> Warm? {
        guard let context else { return nil }
        let header = encode(ChatML.open(system: system) + ChatML.transcriptOpen)
        guard let cache = try? context.model.newCache(parameters: nil) else { return nil }
        prefill(header, into: cache)
        return Warm(system: system, lines: [], tokenCount: header.count, cache: cache)
    }

    /// The lines the warm cache should hold. It starts where the current cache starts, so the
    /// prefix stays append-only; once that grows past the budget it's cut back to the newest
    /// lines that fit a smaller target, so the (background) rebuild happens rarely.
    private func fitted(_ lines: [PrefixLine]) -> [PrefixLine] {
        var start = 0
        if let first = warm?.lines.first, let index = lines.firstIndex(of: first) { start = index }
        let total = lines[start...].reduce(0) { $0 + tokens(for: $1).count }
        guard total > maxWarmTokens else { return Array(lines[start...]) }
        var kept = 0
        var cut = lines.count
        while cut > 0, kept + tokens(for: lines[cut - 1]).count <= rebuiltWarmTokens {
            cut -= 1
            kept += tokens(for: lines[cut]).count
        }
        return Array(lines[cut...])
    }

    private func tokens(for line: PrefixLine) -> [Int] {
        if let cached = lineTokens[line.key], cached.text == line.text { return cached.tokens }
        let tokens = encode(line.text + "\n")
        if lineTokens.count > 4_000 { lineTokens.removeAll() }
        lineTokens[line.key] = (line.text, tokens)
        return tokens
    }

    // MARK: Generation

    /// Streams an answer. With `continuing`, an earlier draft for a slightly different prompt
    /// is verified first and its agreeing prefix is reused instead of regenerated.
    @discardableResult
    func generate(_ prompt: LocalPrompt, id: UUID, continuing draftID: UUID?, maxTokens: Int,
                  requestedAt: Date = Date(), onEvent: @Sendable (LocalEvent) -> Void) throws -> [Int] {
        defer { signals.forget(id) }
        guard let context else { throw LocalEngineError.notLoaded }
        guard !signals.isCancelled(id) else { return [] }
        let start = Date()

        // Usually a no-op: the background sync has already prefilled every settled line.
        sync(system: prompt.system, settled: prompt.settled, background: false)
        guard let warm else { throw LocalEngineError.notLoaded }
        var stats = LocalStats(queuedSeconds: start.timeIntervalSince(requestedAt),
                               syncSeconds: Date().timeIntervalSince(start), reusedTokens: warm.tokenCount)
        let input = encode(ChatML.close(tail: prompt.tail))
        stats.prefillTokens = input.count

        // With a draft to continue, the prompt (minus its last token) is prefilled once and
        // shared: verification scores the draft on a copy, and generation resumes from it.
        let cache: [KVCache]
        var feed = input
        var carried: [Int] = []
        if let draftID, let draft = outputs[draftID], !draft.isEmpty, let last = input.last {
            let base = warm.cache.map { $0.copy() }
            prefill(Array(input.dropLast()), into: base)
            carried = verify(draft, after: last, on: base)
            onEvent(.replace(context.tokenizer.decode(tokenIds: carried)))
            stats.carriedTokens = carried.count
            cache = base
            feed = [last] + carried
        } else {
            cache = warm.cache.map { $0.copy() }
        }

        let parameters = GenerateParameters(maxTokens: max(1, maxTokens - carried.count), temperature: 0)
        let lmInput = LMInput(tokens: MLXArray(feed.map(Int32.init)))
        var iterator: any TokenIteratorProtocol
        if let drafter, mtpEnabled {
            iterator = try MTPSpeculativeTokenIterator(
                input: lmInput, mainModel: context.model, drafter: drafter, mainCache: cache,
                parameters: parameters, blockSize: mtpBlockSize)
        } else {
            iterator = try TokenIterator(input: lmInput, model: context.model, cache: cache, parameters: parameters)
        }

        var detokenizer = NaiveStreamingDetokenizer(tokenizer: context.tokenizer)
        for token in carried { detokenizer.append(token: token) }
        _ = detokenizer.next()

        var generated = carried
        var firstToken: Date?
        while let token = iterator.next() {
            if signals.isCancelled(id) || stopTokens.contains(token) { break }
            if firstToken == nil { firstToken = Date() }
            generated.append(token)
            detokenizer.append(token: token)
            if let text = detokenizer.next(), !text.isEmpty { onEvent(.delta(text)) }
            if generated.count >= maxTokens { break }
        }

        let end = Date()
        let fresh = generated.count - carried.count
        stats.generatedTokens = fresh
        stats.firstTokenSeconds = (firstToken ?? end).timeIntervalSince(start)
        if let firstToken, fresh > 1 {
            stats.tokensPerSecond = Double(fresh - 1) / max(end.timeIntervalSince(firstToken), 1e-3)
        }
        if let mtp = iterator as? MTPSpeculativeTokenIterator, mtp.proposedCount > 0 {
            stats.draftAcceptance = Double(mtp.acceptedCount) / Double(mtp.proposedCount)
        }
        remember(generated, for: id)
        onEvent(.finished(stats))
        return generated
    }

    /// PredGen greedy verification: score the old draft under the new prompt and keep the
    /// longest prefix the model would have written itself. Drafts that diverge usually do so
    /// within a few tokens, so the first pass scores only 16; the rest is scored in one more
    /// pass only if those all agree. `base` holds the prompt minus `last` and isn't modified.
    private func verify(_ draft: [Int], after last: Int, on base: [KVCache]) -> [Int] {
        guard let context else { return [] }
        let draft = Array(draft.prefix(320))
        let probe = base.map { $0.copy() }
        var feed = [last] + draft.prefix(16)
        var predicts = 0  // the draft index the first logit of `feed` predicts
        var accepted = 0
        while !feed.isEmpty {
            let output = context.model(
                LMInput.Text(tokens: MLXArray(feed.map(Int32.init)).reshaped([1, feed.count])), cache: probe, state: nil)
            let predicted = argMax(output.logits[0], axis: -1).asArray(Int32.self)
            for (offset, token) in predicted.enumerated() {
                let index = predicts + offset
                guard index < draft.count else { return draft }
                guard Int(token) == draft[index] else { return Array(draft[..<accepted]) }
                accepted = index + 1
            }
            predicts += feed.count
            let start = predicts - 1
            guard start < draft.count else { return draft }
            feed = Array(draft[start..<min(start + 256, draft.count)])
        }
        return Array(draft[..<accepted])
    }

    /// SpeculativeETD-style check: the probability that the transcript's last utterance
    /// expects a reply from the user. Costs one short prefill on a fork of the warm cache.
    func expectsReply(_ prompt: LocalPrompt) -> Double? {
        guard let context else { return nil }
        sync(system: prompt.system, settled: prompt.settled, background: false)
        guard let warm,
              let yes = encode("Yes").first, let no = encode("No").first else { return nil }
        let input = encode(ChatML.close(tail: prompt.tail))
        let cache = warm.cache.map { $0.copy() }
        prefill(Array(input.dropLast()), into: cache)
        let output = context.model(
            LMInput.Text(tokens: MLXArray([Int32(input.last!)]).reshaped([1, 1])), cache: cache, state: nil)
        let logits = output.logits[0, -1].asType(.float32)
        let pair = softmax(stacked([logits[yes], logits[no]]))
        return Double(pair[0].item(Float.self))
    }

    // MARK: Plumbing

    private func prefill(_ tokens: [Int], into cache: [KVCache]) {
        guard let context, !tokens.isEmpty else { return }
        var done = 0
        while done < tokens.count {
            let end = min(done + prefillStep, tokens.count)
            let chunk = tokens[done..<end].map(Int32.init)
            // Only the cache is evaluated, so MLX never computes the (unused) logits.
            _ = context.model(LMInput.Text(tokens: MLXArray(chunk).reshaped([1, chunk.count])), cache: cache, state: nil)
            eval(cache)
            done = end
        }
    }

    private func encode(_ text: String) -> [Int] {
        context?.tokenizer.encode(text: text, addSpecialTokens: false) ?? []
    }

    private func remember(_ tokens: [Int], for id: UUID) {
        outputs[id] = tokens
        outputOrder.append(id)
        while outputOrder.count > 8 { outputs[outputOrder.removeFirst()] = nil }
    }

    // MARK: Diagnostics

    /// Raw prefill throughput for `count` tokens fed in chunks of `chunk`.
    func measurePrefill(count: Int, chunk: Int) -> Double {
        guard let context, let cache = try? context.model.newCache(parameters: nil) else { return 0 }
        let tokens = (0..<count).map { 1000 + ($0 * 7919) % 50_000 }
        let start = Date()
        var done = 0
        while done < count {
            let end = min(done + chunk, count)
            let piece = tokens[done..<end].map(Int32.init)
            _ = context.model(LMInput.Text(tokens: MLXArray(piece).reshaped([1, piece.count])), cache: cache, state: nil)
            eval(cache)
            done = end
        }
        return Double(count) / Date().timeIntervalSince(start)
    }

    func diagnostics() -> (warmTokens: Int, warmLines: Int, activeMB: Int) {
        (warm?.tokenCount ?? 0, warm?.lines.count ?? 0, Memory.activeMemory >> 20)
    }

    /// Exposes the tokenizer's own chat template so the benchmark can check `ChatML` against it.
    func templateTokens(system: String, user: String) throws -> (template: [Int], manual: [Int]) {
        guard let context else { throw LocalEngineError.notLoaded }
        let template = try context.tokenizer.applyChatTemplate(
            messages: [["role": "system", "content": system], ["role": "user", "content": user]],
            tools: nil, additionalContext: ["enable_thinking": false])
        let manual = encode(ChatML.open(system: system)) + encode(ChatML.close(tail: user))
        return (template, manual)
    }
}

/// Qwen's chat format, rendered by hand so the transcript prefix stays byte-stable and
/// append-only: system and the opening of the user turn first, then transcript lines,
/// then the closing tail. Thinking is switched off: answers start on the first token.
enum ChatML {
    /// Opens the transcript inside the user turn; settled lines follow, and the tail closes it.
    static let transcriptOpen = "<transcript>\n"

    static func open(system: String) -> String {
        "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n"
    }

    static func close(tail: String) -> String {
        "\(tail)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }
}

import Foundation

struct LLMRequest: Sendable {
    var system: String
    var text: String
    var imageJPEG: Data?
    /// A problem to solve (code, a screenshot of one, math): reason harder and leave room for a
    /// full solution, instead of optimizing for the fastest first word.
    var deep = false
    /// Quick, the usual few points, or the full in-depth answer.
    var length = AnswerLength.standard

    /// Long reasoning can go quiet on the wire for a while.
    var timeout: TimeInterval { deep || length == .detailed ? 300 : 90 }
}

/// What a provider streams back.
enum LLMEvent: Sendable {
    case text(String)
    /// The model is reasoning; its thoughts aren't shown.
    case thinking
}

enum LLMError: LocalizedError {
    case http(AIProvider, Int, String)
    case api(String)
    case refusal(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let provider, 401, _), .http(let provider, 403, _):
            "\(provider.label) rejected the API key. Check it in Settings."
        case .http(let provider, 429, let message):
            "\(provider.label) rate limit: \(message)"
        case .http(let provider, let code, _) where code == 529 || code == 503:
            "\(provider.label) is overloaded right now. Try again in a moment."
        case .http(let provider, let code, let message):
            "\(provider.label) error \(code): \(message)"
        case .api(let message):
            message
        case .refusal(let message):
            message
        case .badResponse:
            "Unexpected response from the model."
        }
    }
}

/// Streams answer text from whichever provider is selected in Settings.
enum LLMClient {
    static func stream(_ request: LLMRequest, provider: AIProvider, model: String, apiKey: String) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let emit: (LLMEvent) -> Void = { continuation.yield($0) }
                    switch provider {
                    case .local: throw LLMError.api("On-device answers don't go through the network client.")
                    case .claude: try await ClaudeClient.run(request, model: ClaudeModel.named(model), apiKey: apiKey, onEvent: emit)
                    case .openRouter: try await OpenRouterClient.run(request, model: model, apiKey: apiKey, onEvent: emit)
                    case .gemini: try await GeminiClient.run(request, model: model, apiKey: apiKey, onEvent: emit)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Shared SSE plumbing

enum SSE {
    /// Sends the request and returns the event-stream lines, turning a non-200 into a readable error.
    static func open(_ request: URLRequest, provider: AIProvider) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        guard http.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 32_768 { break }
            }
            let message = errorMessage(in: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw LLMError.http(provider, http.statusCode, message)
        }
        return bytes.lines
    }

    /// The JSON payload of a `data:` line, or nil for comments, blank lines and `[DONE]`.
    static func payload(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("data:") else { return nil }
        let body = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard body != "[DONE]" else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
    }

    /// Pulls `error.message` out of the error shapes used by Anthropic, OpenRouter and Google.
    static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let dict = (object as? [String: Any]) ?? (object as? [[String: Any]])?.first
        return errorMessage(in: dict ?? [:])
    }

    static func errorMessage(in object: [String: Any]) -> String? {
        guard let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    static func jsonRequest(_ url: URL, body: [String: Any], headers: [String: String], timeout: TimeInterval = 90) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Claude (Anthropic Messages API)

/// There's no official Swift SDK, so this is raw HTTP + SSE against /v1/messages.
enum ClaudeClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func run(_ request: LLMRequest, model: ClaudeModel, apiKey: String, onEvent: (LLMEvent) -> Void) async throws {
        do {
            try await run(request, model: model, apiKey: apiKey, fallbacks: model.fallbacks, onEvent: onEvent)
        } catch LLMError.http(_, 400, let message) where model.fallbacks && message.lowercased().contains("fallback") {
            // Account without the fallback beta: retry as a plain request.
            try await run(request, model: model, apiKey: apiKey, fallbacks: false, onEvent: onEvent)
        }
    }

    private static func run(_ request: LLMRequest, model: ClaudeModel, apiKey: String, fallbacks: Bool, onEvent: (LLMEvent) -> Void) async throws {
        var content: [[String: Any]] = []
        if let jpeg = request.imageJPEG {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": request.text])

        var body: [String: Any] = [
            "model": model.id,
            // Thinking counts toward this, so a problem gets room for reasoning and a full
            // solution. Streaming keeps a large cap safe from HTTP timeouts.
            "max_tokens": request.deep ? 64_000 : 16_000,
            "stream": true,
            // The system prompt (profile, prerequisites, pasted docs) is identical across a
            // meeting; caching it skips re-processing it on every answer. Below the minimum
            // cacheable length the marker is simply ignored.
            "system": [["type": "text", "text": request.system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": content]],
        ]
        var headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        // Live meetings need fast first tokens; low effort keeps thinking short. Solving a
        // problem is intelligence-sensitive work, where Anthropic recommends at least `high`.
        // Effort also governs how much text the reply spends, so at `low` an elaborate answer
        // comes back as a summary whatever the prompt asks.
        body["output_config"] = ["effort": request.deep ? "high" : request.length == .detailed ? "medium" : "low"]
        if fallbacks {
            // Re-runs a safety-classifier decline on Anthropic's recommended fallback model.
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
        }

        let lines = try await SSE.open(try SSE.jsonRequest(endpoint, body: body, headers: headers, timeout: request.timeout), provider: .claude)
        for try await line in lines {
            guard let event = SSE.payload(line), let type = event["type"] as? String else { continue }
            switch type {
            case "content_block_start":
                if let block = event["content_block"] as? [String: Any], (block["type"] as? String)?.contains("thinking") == true {
                    onEvent(.thinking)
                }
            case "content_block_delta":
                // Thinking and fallback blocks are skipped; only visible text is shown.
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String {
                    onEvent(.text(text))
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                    throw LLMError.refusal("Claude declined to answer this one.")
                }
            case "error":
                throw LLMError.api(SSE.errorMessage(in: event) ?? "Claude stream error")
            default:
                break
            }
        }
    }
}

// MARK: - OpenRouter (OpenAI-compatible chat completions)

enum OpenRouterClient {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    static func run(_ request: LLMRequest, model: String, apiKey: String, onEvent: (LLMEvent) -> Void) async throws {
        let info = await OpenRouterCatalog.shared.info(for: model)
        do {
            try await run(request, model: model, info: info, apiKey: apiKey, onEvent: onEvent)
        } catch LLMError.http(_, let code, let message) where request.imageJPEG != nil && (code == 400 || code == 404)
                    && message.lowercased().contains("image") {
            // The model reads text only. Screen requests also carry the screen's OCR text, so
            // answer from that, and skip the image for this model from now on.
            await OpenRouterCatalog.shared.markTextOnly(model)
            var textOnly = request
            textOnly.imageJPEG = nil
            try await run(textOnly, model: model, info: info, apiKey: apiKey, onEvent: onEvent)
        }
    }

    private static func run(_ request: LLMRequest, model: String, info: OpenRouterCatalog.Info?, apiKey: String,
                            onEvent: (LLMEvent) -> Void) async throws {
        var user: [[String: Any]] = [["type": "text", "text": request.text]]
        if let jpeg = request.imageJPEG {
            user.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]])
        }
        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": maxTokens(for: request, info: info),
            "messages": [
                ["role": "system", "content": request.system],
                ["role": "user", "content": user],
            ],
        ]
        if request.deep, info?.reasons == true {
            // OpenRouter's unified reasoning switch; models without reasoning don't list it.
            body["reasoning"] = ["effort": "high"]
        }
        let headers = ["authorization": "Bearer \(apiKey)", "X-OpenRouter-Title": "Assist"]

        let lines = try await SSE.open(try SSE.jsonRequest(endpoint, body: body, headers: headers, timeout: request.timeout),
                                       provider: .openRouter)
        // Lines starting with ":" are keep-alive comments; SSE.payload skips them and [DONE].
        for try await line in lines {
            guard let chunk = SSE.payload(line) else { continue }
            if let message = SSE.errorMessage(in: chunk) {
                throw LLMError.api("OpenRouter: \(message)")
            }
            guard let choice = (chunk["choices"] as? [[String: Any]])?.first else { continue }
            if let delta = choice["delta"] as? [String: Any] {
                if (delta["reasoning"] as? String)?.isEmpty == false || (delta["reasoning_details"] as? [Any])?.isEmpty == false {
                    onEvent(.thinking)
                }
                if let text = delta["content"] as? String, !text.isEmpty {
                    onEvent(.text(text))
                }
            }
            if choice["finish_reason"] as? String == "content_filter" {
                throw LLMError.refusal("The model's content filter stopped this answer.")
            }
        }
    }

    /// Reasoning counts toward `max_tokens` on most providers, so a problem gets far more room,
    /// kept within what the model can produce and what its context has left.
    private static func maxTokens(for request: LLMRequest, info: OpenRouterCatalog.Info?) -> Int {
        var limit = request.deep ? 32_000 : 8_192
        if let cap = info?.maxOutput { limit = min(limit, cap) }
        if let context = info?.context {
            let input = (request.system.count + request.text.count) / 3 + (request.imageJPEG == nil ? 0 : 3_000)
            limit = min(limit, max(1_024, context - input - 512))
        }
        return limit
    }
}

/// What each OpenRouter model can do, from OpenRouter's public model list (fetched once, about
/// 1 MB): whether it reads images, supports reasoning, and how much it can write.
actor OpenRouterCatalog {
    static let shared = OpenRouterCatalog()

    struct Info: Sendable {
        var acceptsImages: Bool
        var reasons: Bool
        var maxOutput: Int?
        var context: Int?
    }

    private var models: [String: Info]?
    private var loading: Task<[String: Info], Never>?
    private var textOnly: Set<String> = []

    /// nil when the list couldn't be fetched or doesn't know the model.
    func info(for model: String) async -> Info? {
        if models == nil {
            let task = loading ?? Task { await Self.fetch() }
            loading = task
            let fetched = await task.value
            loading = nil
            if !fetched.isEmpty { models = fetched }
        }
        var info = models?[model]
        if textOnly.contains(model) {
            info = info ?? Info(acceptsImages: false, reasons: false)
            info?.acceptsImages = false
        }
        return info
    }

    func markTextOnly(_ model: String) { textOnly.insert(model) }

    private static func fetch() async -> [String: Info] {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://openrouter.ai/api/v1/models")!),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["data"] as? [[String: Any]] else { return [:] }
        var models: [String: Info] = [:]
        for model in list {
            guard let id = model["id"] as? String else { continue }
            let inputs = (model["architecture"] as? [String: Any])?["input_modalities"] as? [String]
            let provider = model["top_provider"] as? [String: Any]
            models[id] = Info(acceptsImages: inputs?.contains("image") ?? true,
                              reasons: (model["supported_parameters"] as? [String])?.contains("reasoning") ?? false,
                              maxOutput: provider?["max_completion_tokens"] as? Int,
                              context: (provider?["context_length"] as? Int) ?? (model["context_length"] as? Int))
        }
        return models
    }
}

// MARK: - Gemini (Google AI generateContent)

enum GeminiClient {
    static func run(_ request: LLMRequest, model: String, apiKey: String, onEvent: (LLMEvent) -> Void) async throws {
        let name = model.hasPrefix("models/") ? String(model.dropFirst("models/".count)) : model
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded):streamGenerateContent?alt=sse") else {
            throw LLMError.api("Invalid Gemini model name: \(model)")
        }

        var parts: [[String: Any]] = []
        if let jpeg = request.imageJPEG {
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        parts.append(["text": request.text])
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.system]]],
            "contents": [["role": "user", "parts": parts]],
            // Thinking counts toward the output limit; Gemini 2.5 and later can write 64K.
            "generationConfig": ["maxOutputTokens": request.deep && writesLong(name) ? 32_768 : 8_192],
        ]

        let lines = try await SSE.open(try SSE.jsonRequest(url, body: body, headers: ["x-goog-api-key": apiKey], timeout: request.timeout),
                                       provider: .gemini)
        var producedText = false
        for try await line in lines {
            guard let chunk = SSE.payload(line) else { continue }
            if let message = SSE.errorMessage(in: chunk) {
                throw LLMError.api("Gemini: \(message)")
            }
            if let feedback = chunk["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
                throw LLMError.refusal("Gemini blocked this request (\(reason.lowercased())).")
            }
            guard let candidate = (chunk["candidates"] as? [[String: Any]])?.first else { continue }
            let partsOut = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            for part in partsOut {
                if part["thought"] as? Bool == true { onEvent(.thinking); continue }
                if let text = part["text"] as? String, !text.isEmpty {
                    producedText = true
                    onEvent(.text(text))
                }
            }
            if let finish = candidate["finishReason"] as? String,
               ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"].contains(finish), !producedText {
                throw LLMError.refusal("Gemini declined to answer this one.")
            }
        }
    }
}

extension GeminiClient {
    /// Gemini 2.5 and later accept a 64K output limit; earlier models stop at 8K.
    static func writesLong(_ name: String) -> Bool {
        guard let match = name.firstMatch(of: #/gemini-(\d+(?:\.\d+)?)/#), let version = Double(match.1) else { return false }
        return version >= 2.5
    }
}

// MARK: - Model lists for the Settings pickers

enum ModelCatalog {
    /// Public list; no key needed.
    static func openRouterModels() async throws -> [String] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://openrouter.ai/api/v1/models")!)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = object?["data"] as? [[String: Any]] ?? []
        return models.compactMap { $0["id"] as? String }.filter { !$0.hasSuffix(":batch") }
    }

    static func geminiModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=500")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LLMError.http(.gemini, http.statusCode, SSE.errorMessage(in: data) ?? "Couldn't list models")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = object?["models"] as? [[String: Any]] ?? []
        return models.compactMap { model -> String? in
            guard let name = model["name"] as? String,
                  (model["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { return nil }
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
        .filter { $0.hasPrefix("gemini") && !$0.contains("tts") && !$0.contains("image") && !$0.contains("embedding") }
    }
}

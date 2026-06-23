import Foundation

enum LLMError: Error, CustomStringConvertible, LocalizedError {
    case noKey
    case badURL
    case http(Int, String)
    case badResponse

    var description: String {
        switch self {
        case .noKey:
            return AppFlavor.text("缺少 API Key", "API key is missing")
        case .badURL:
            return AppFlavor.text("Base URL 无效", "Base URL is invalid")
        case .http(let code, let body):
            let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = clean.isEmpty ? AppFlavor.text("服务没有返回错误详情", "The service returned no error detail") : String(clean.prefix(260))
            return "HTTP \(code): \(message)"
        case .badResponse:
            return AppFlavor.text("响应格式无法解析", "Response could not be parsed")
        }
    }

    var errorDescription: String? { description }
}

/// Text actions via an OpenAI-compatible Chat Completions API.
/// Takes a system prompt (from the action) + the selected text.
enum LLMClient {

    static func complete(prompt: String, text: String, provider: LLMProviderConfig? = nil) async throws -> String {
        let config = provider ?? Settings.defaultLLMProvider
        let key = config.apiKey
        guard !key.isEmpty else { throw LLMError.noKey }
        guard let url = chatCompletionsURL(baseURL: config.baseURL) else { throw LLMError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: requestBody(prompt: prompt, text: text, stream: false, model: config.model))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.badResponse }
        guard http.statusCode == 200 else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw LLMError.badResponse }
        return LLMOutputSanitizer.visibleAnswer(from: content)
    }

    static func testConnection(provider: LLMProviderConfig) async throws -> String {
        let response = try await complete(
            prompt: AppFlavor.text("你是 API 连通性检测器。只回复 OK 两个字母，不要解释。",
                                   "You are an API connectivity checker. Reply with only OK, no explanation."),
            text: "ping",
            provider: provider
        )
        guard !response.isEmpty else { throw LLMError.badResponse }
        return response
    }

    /// Streaming variant — yields text deltas as they arrive (SSE).
    static func stream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        stream(prompt: prompt, text: text, provider: Settings.defaultLLMProvider)
    }

    static func stream(prompt: String, text: String, provider: LLMProviderConfig) -> AsyncThrowingStream<String, Error> {
        stream(messages: [
            ["role": "system", "content": systemContent(prompt)],
            ["role": "user", "content": text]
        ], provider: provider)
    }

    /// Multi-turn streaming. The caller owns the full messages array; the
    /// plain-text / no-Markdown rule must already be folded into the system
    /// message via `systemContent(_:)` (so it is injected exactly once).
    static func stream(messages: [[String: String]], provider: LLMProviderConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = provider.apiKey
                    guard !key.isEmpty else { throw LLMError.noKey }
                    guard let url = chatCompletionsURL(baseURL: provider.baseURL) else { throw LLMError.badURL }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": provider.model,
                        "messages": messages,
                        "stream": true
                    ])

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw LLMError.badResponse }
                    guard http.statusCode == 200 else { throw LLMError.http(http.statusCode, "") }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let chunk = delta["content"] as? String, !chunk.isEmpty else { continue }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// System message content = base prompt + the plain-text / no-Markdown rule.
    static func systemContent(_ basePrompt: String) -> String {
        basePrompt + "\n\n" + plainTextRule
    }

    /// Appended to every action prompt: the answer is read aloud by TTS, so it
    /// must be plain spoken text with no Markdown — otherwise TTS literally reads
    /// out "井号 / 星号" etc.
    private static var plainTextRule: String {
        AppFlavor.text(
            "输出要求：你的回答会被语音合成直接朗读，必须是纯文本口语，绝对不要使用任何 Markdown 或排版符号——不要 # 标题、不要 * 或 ** 加粗、不要反引号、不要 - 或 1. 2. 之类的列表符号、不要表格或分隔线。不要输出思考过程、推理过程、<think>、reasoning 或 analysis 内容，只给用户可见的最终答案。需要分点时用「首先」「其次」「最后」或顿号、逗号自然连接成话。",
            "Output requirement: your answer will be read aloud by text-to-speech, so it must be natural spoken plain text. Do not use Markdown or formatting symbols: no headings, asterisks, backticks, bullet symbols, numbered lists, tables, or separators. Do not output hidden thinking, reasoning, <think>, analysis, or chain-of-thought content; return only the final user-visible answer. If structure is needed, use spoken transitions like first, next, finally, or connect ideas naturally in sentences."
        )
    }

    private static func chatCompletionsURL(baseURL: String) -> URL? {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        if normalized.lowercased().hasSuffix("/chat/completions") {
            return URL(string: normalized)
        }
        return URL(string: normalized + "/chat/completions")
    }

    private static func requestBody(prompt: String, text: String, stream: Bool, model: String) -> [String: Any] {
        [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt + "\n\n" + plainTextRule],
                ["role": "user", "content": text]
            ],
            "stream": stream
        ]
    }
}

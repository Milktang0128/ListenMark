import Foundation

enum LLMError: Error {
    case noKey
    case http(Int, String)
    case badResponse
}

/// Text actions via DeepSeek's OpenAI-compatible Chat Completions API.
/// Takes a system prompt (from the action) + the selected text.
enum LLMClient {

    static func complete(prompt: String, text: String) async throws -> String {
        let key = Settings.deepseekKey
        guard !key.isEmpty else { throw LLMError.noKey }

        var req = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: requestBody(prompt: prompt, text: text, stream: false))

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
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streaming variant — yields text deltas as they arrive (SSE).
    static func stream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = Settings.deepseekKey
                    guard !key.isEmpty else { throw LLMError.noKey }

                    var req = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: requestBody(prompt: prompt, text: text, stream: true))

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

    /// Appended to every action prompt: the answer is read aloud by TTS, so it
    /// must be plain spoken text with no Markdown — otherwise TTS literally reads
    /// out "井号 / 星号" etc.
    private static let plainTextRule =
        "输出要求：你的回答会被语音合成直接朗读，必须是纯文本口语，绝对不要使用任何 Markdown 或排版符号——不要 # 标题、不要 * 或 ** 加粗、不要反引号、不要 - 或 1. 2. 之类的列表符号、不要表格或分隔线。需要分点时用「首先」「其次」「最后」或顿号、逗号自然连接成话。"

    private static func requestBody(prompt: String, text: String, stream: Bool) -> [String: Any] {
        [
            "model": Settings.deepseekModel,
            "messages": [
                ["role": "system", "content": prompt + "\n\n" + plainTextRule],
                ["role": "user", "content": text]
            ],
            "stream": stream
        ]
    }
}

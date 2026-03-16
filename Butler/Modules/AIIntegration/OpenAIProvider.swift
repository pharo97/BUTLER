import Foundation

// MARK: - OpenAIProvider

/// OpenAI GPT implementation of `ModelProvider`.
///
/// Streams via the Chat Completions API using Server-Sent Events.
/// Yields one token per `choices[0].delta.content` chunk.
///
/// Note: OpenAI doesn't use a separate `system` parameter — the system
/// prompt is injected as the first message with role "system".
struct OpenAIProvider: ModelProvider {

    // MARK: - ModelProvider metadata

    var displayName:       String { "GPT-4 (OpenAI)" }
    var defaultModel:      String { "gpt-4o" }
    var availableModels:   [String] { ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"] }
    var apiKeyPlaceholder: String { "sk-proj-…" }
    var apiKeyURL: URL { URL(string: "https://platform.openai.com/api-keys")! }

    // MARK: - Private constants

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    // MARK: - ModelProvider streaming

    func stream(
        messages:  [[String: String]],
        system:    String,
        apiKey:    String,
        model:     String,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {

        let resolvedModel = model.isEmpty ? defaultModel : model

        // OpenAI embeds the system prompt as the first message.
        // Build as `let` so Swift 6 can safely capture it in the Task closure.
        let systemMsg: [[String: String]] = system.isEmpty
            ? []
            : [["role": "system", "content": system]]
        let fullMessages: [[String: String]] = systemMsg + messages

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var request          = URLRequest(url: Self.endpoint)
                    request.httpMethod   = "POST"
                    request.timeoutInterval = 30
                    request.setValue("application/json",     forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)",     forHTTPHeaderField: "Authorization")

                    let body: [String: Any] = [
                        "model":      resolvedModel,
                        "max_tokens": maxTokens,
                        "stream":     true,
                        "messages":   fullMessages
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw ProviderError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        throw ProviderError.httpError(http.statusCode, provider: "OpenAI")
                    }

                    // Parse OpenAI SSE chunks
                    // Format: data: {"choices":[{"delta":{"content":"hello"},"finish_reason":null}]}
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }

                        guard
                            let data    = payload.data(using: .utf8),
                            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let choices = json["choices"] as? [[String: Any]],
                            let first   = choices.first,
                            let delta   = first["delta"] as? [String: Any],
                            let text    = delta["content"] as? String,
                            !text.isEmpty
                        else { continue }

                        continuation.yield(text)
                    }
                    continuation.finish()

                } catch let e as ProviderError {
                    continuation.finish(throwing: e)
                } catch {
                    continuation.finish(throwing: ProviderError.network(error))
                }
            }
        }
    }
}

import Foundation

// MARK: - ClaudeProvider

/// Anthropic Claude implementation of `ModelProvider`.
///
/// Streams via the Messages API using Server-Sent Events.
/// Yields one token per `content_block_delta` SSE event.
struct ClaudeProvider: ModelProvider {

    // MARK: - ModelProvider metadata

    var displayName:      String { "Claude (Anthropic)" }
    var defaultModel:     String { "claude-sonnet-4-6" }
    var availableModels:  [String] { ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-6"] }
    var apiKeyPlaceholder: String { "sk-ant-api03-…" }
    var apiKeyURL: URL { URL(string: "https://console.anthropic.com/settings/keys")! }

    // MARK: - Private constants

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - ModelProvider streaming

    func stream(
        messages:  [[String: String]],
        system:    String,
        apiKey:    String,
        model:     String,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {

        let resolvedModel = model.isEmpty ? defaultModel : model

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var request          = URLRequest(url: Self.endpoint)
                    request.httpMethod   = "POST"
                    request.timeoutInterval = 30
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")

                    let body: [String: Any] = [
                        "model":      resolvedModel,
                        "max_tokens": maxTokens,
                        "stream":     true,
                        "system":     system,
                        "messages":   messages
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw ProviderError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        throw ProviderError.httpError(http.statusCode, provider: "Claude")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }

                        guard
                            let data  = payload.data(using: .utf8),
                            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            (json["type"] as? String) == "content_block_delta",
                            let delta = json["delta"] as? [String: Any],
                            (delta["type"] as? String) == "text_delta",
                            let text  = delta["text"] as? String,
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

// MARK: - ProviderError (shared across all providers)

/// Errors that any `ModelProvider` implementation can throw.
enum ProviderError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int, provider: String)
    case network(Error)
    case noKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from the AI provider."
        case .httpError(let code, let name):
            return "\(name) returned HTTP \(code). Check your API key and billing status."
        case .network(let e):
            return "Network error: \(e.localizedDescription)"
        case .noKey:
            return "No API key configured for this provider."
        }
    }
}

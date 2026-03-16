import Foundation

// MARK: - OllamaProvider

/// Local Ollama LLM implementation of `ModelProvider`.
///
/// Talks to the Ollama server running at `http://localhost:11434` using the
/// `/api/chat` streaming endpoint. No API key is required — Ollama runs
/// entirely on-device.
///
/// ## Quick setup
/// ```bash
/// brew install ollama
/// ollama serve                # starts the server
/// ollama pull llama3.2        # or mistral, codellama, gemma3, phi4, etc.
/// ```
///
/// After pulling a model, select it in BUTLER Settings → AI Provider → Ollama.
///
/// ## Streaming format
/// Ollama streams newline-delimited JSON objects (not SSE).
/// Each line: `{"model":"…","message":{"role":"assistant","content":"token"},"done":false}`
/// Final line has `"done": true`.
///
/// ## Timeout strategy
/// Ollama can take 20-60s to cold-load a large model on the first request.
/// We use a 120s request timeout to accommodate this without a false failure.
/// The fast `isReachable()` check (3s) is used ONLY in Settings to show a
/// status badge — NOT as a blocking pre-flight before streaming. This ensures
/// a slow Ollama startup doesn't abort the pipeline before the model loads.
struct OllamaProvider: ModelProvider {

    // MARK: - ModelProvider metadata

    var displayName:       String { "Ollama (Local)" }
    var defaultModel:      String { "llama3.2" }
    /// Hardcoded fallback list shown when Ollama is offline or no tags fetch has run.
    var availableModels:   [String] {
        ["llama3.2", "llama3.2:1b", "mistral", "codellama", "gemma3", "phi4", "qwen2.5", "deepseek-r1"]
    }
    var apiKeyPlaceholder: String { "No key required" }
    var apiKeyURL:         URL    { URL(string: "https://ollama.com/download")! }
    /// Ollama is local — no API key needed.
    var requiresApiKey:    Bool   { false }

    // MARK: - Endpoints

    static let chatEndpoint = URL(string: "http://localhost:11434/api/chat")!
    static let tagsEndpoint = URL(string: "http://localhost:11434/api/tags")!

    // MARK: - ModelProvider streaming

    func stream(
        messages:  [[String: String]],
        system:    String,
        apiKey:    String,              // ignored — Ollama is local
        model:     String,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {

        let resolvedModel = model.isEmpty ? defaultModel : model

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var request             = URLRequest(url: Self.chatEndpoint)
                    request.httpMethod      = "POST"
                    // 120s timeout — covers cold model load (llama3.2 ~30-60s first run).
                    // Do NOT use isReachable() as a blocking pre-flight here: if Ollama
                    // is mid-startup, tags returns 503 while chat still works. We let the
                    // actual request fail with a clear error rather than aborting early.
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    // Ollama chat format: system is a message with role "system"
                    var ollamaMessages: [[String: String]] = []
                    if !system.isEmpty {
                        ollamaMessages.append(["role": "system", "content": system])
                    }
                    ollamaMessages.append(contentsOf: messages)

                    let body: [String: Any] = [
                        "model":    resolvedModel,
                        "messages": ollamaMessages,
                        "stream":   true,
                        "options":  ["num_predict": maxTokens]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: request)
                    } catch let urlError as URLError {
                        // Connection refused = Ollama is not running. Surface a clear message.
                        if urlError.code == .cannotConnectToHost
                            || urlError.code == .networkConnectionLost
                            || urlError.code == .timedOut {
                            throw ProviderError.httpError(
                                503,
                                provider: "Ollama (not running — run: ollama serve)"
                            )
                        }
                        throw ProviderError.network(urlError)
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw ProviderError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        // 404 = model not pulled. Surface actionable message.
                        if http.statusCode == 404 {
                            throw ProviderError.httpError(
                                404,
                                provider: "Ollama (model '\(resolvedModel)' not found — run: ollama pull \(resolvedModel))"
                            )
                        }
                        throw ProviderError.httpError(http.statusCode, provider: "Ollama")
                    }

                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }
                        guard
                            let data    = line.data(using: .utf8),
                            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        // Final frame — stop consuming
                        if let done = json["done"] as? Bool, done { break }

                        // Extract token from message delta
                        if let msg     = json["message"] as? [String: Any],
                           let content = msg["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
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

    // MARK: - Health check + model discovery

    /// Returns `true` if the local Ollama server is reachable (3 s timeout).
    ///
    /// Used in Settings UI as a status badge. NOT used as a pre-flight before
    /// streaming — see the timeout strategy comment above.
    static func isReachable() async -> Bool {
        var req             = URLRequest(url: tagsEndpoint)
        req.timeoutInterval = 3
        let result          = try? await URLSession.shared.data(for: req)
        guard let (_, response) = result,
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Queries Ollama's `/api/tags` endpoint and returns the sorted list of
    /// installed model names (e.g. `["codellama:latest", "llama3.2:latest", …]`).
    ///
    /// Returns an empty array if Ollama is not running or unreachable (3s timeout).
    static func fetchInstalledModels() async -> [String] {
        var request             = URLRequest(url: tagsEndpoint)
        request.timeoutInterval = 3     // fail fast if Ollama isn't running
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http   = response as? HTTPURLResponse,
                http.statusCode == 200,
                let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let models = json["models"] as? [[String: Any]]
            else { return [] }
            return models.compactMap { $0["name"] as? String }.sorted()
        } catch {
            return []
        }
    }
}

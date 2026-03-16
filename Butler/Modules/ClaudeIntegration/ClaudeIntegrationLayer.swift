import Observation
import Foundation

// MARK: - AIIntegrationLayer

/// Provider-agnostic façade for all LLM interactions.
///
/// Responsibilities:
///   - Owns provider selection (Claude / OpenAI / …) persisted to UserDefaults
///   - Manages API key per provider (Keychain-backed)
///   - Owns ContextWindowManager (in-memory conversation history)
///   - Streams responses, accumulating tokens live for the UI
///
/// Adding a new provider requires only:
///   1. A new `ModelProvider` conformance
///   2. A new case in `AIProviderType`
///   No changes needed here.
@MainActor
@Observable
final class AIIntegrationLayer {

    // MARK: - Observable state

    /// Currently selected provider (persists across launches).
    var selectedProvider: AIProviderType = .claude {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "butler.selectedProvider")
            loadApiKey()
        }
    }

    /// Active model identifier (defaults to provider's recommended model).
    /// Persisted per-provider in UserDefaults so switching providers restores
    /// the last chosen model for each one independently.
    var selectedModel: String = "" {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "butler.model.\(selectedProvider.rawValue)")
        }
    }

    /// Loaded API key for the current provider (empty if not configured).
    private(set) var apiKey: String = ""

    /// Whether a request is currently streaming.
    private(set) var isStreaming: Bool = false

    /// Token-by-token accumulation of the current response (drives live UI).
    private(set) var streamingText: String = ""

    /// Last complete exchange — shown in the conversation panel when idle.
    private(set) var lastUserMessage: String = ""
    private(set) var lastResponse:    String = ""

    /// Set to true when no key exists for the current provider → shows setup sheet.
    var showApiKeySetup: Bool = false

    // MARK: - Private

    private let contextManager = ContextWindowManager()

    // MARK: - Init

    init() {
        // Restore saved provider selection
        if let raw   = UserDefaults.standard.string(forKey: "butler.selectedProvider"),
           let saved = AIProviderType(rawValue: raw) {
            selectedProvider = saved
        }
        loadApiKey()
    }

    // MARK: - API Key management

    func loadApiKey() {
        let provider = selectedProvider.provider

        if provider.requiresApiKey {
            // Cloud providers: load key from Keychain; show setup sheet if missing
            apiKey          = (try? KeychainService.load(for: selectedProvider)) ?? ""
            showApiKeySetup = apiKey.isEmpty
        } else {
            // Local providers (Ollama): no key needed — use placeholder to pass guard checks
            apiKey          = "local"
            showApiKeySetup = false
        }

        // Restore the last selected model for this provider, falling back to the default
        selectedModel = UserDefaults.standard.string(forKey: "butler.model.\(selectedProvider.rawValue)")
                        ?? provider.defaultModel
    }

    /// Persists `key` for the current provider and dismisses the setup sheet.
    func saveApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainService.save(trimmed, for: selectedProvider)
            apiKey          = trimmed
            showApiKeySetup = false
        } catch {
            print("[BUTLER] Keychain save failed: \(error.localizedDescription)")
        }
    }

    /// Dismisses the setup sheet without saving a key (for UI preview / testing).
    func skipSetup() {
        showApiKeySetup = false
    }

    /// Removes the current provider's key and re-shows the setup sheet.
    /// No-op for local providers that don't use the Keychain.
    func clearApiKey() {
        guard selectedProvider.provider.requiresApiKey else { return }
        KeychainService.delete(for: selectedProvider)
        apiKey          = ""
        showApiKeySetup = true
        contextManager.clear()
        lastUserMessage = ""
        lastResponse    = ""
        streamingText   = ""
    }

    // MARK: - Send

    /// Sends `userText` to the active provider, streams the response, returns full text.
    ///
    /// Updates `streamingText` token-by-token while in flight so the conversation
    /// panel reflects the response as it arrives. Caller awaits the return value
    /// before starting TTS.
    /// Pass `context`, `appName`, and optional `screenContext` for full situational awareness.
    func send(
        _ userText: String,
        context: ButlerContext = .unknown,
        appName: String = "",
        screenContext: ScreenContext? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            showApiKeySetup = true
            throw SendError.noApiKey(provider: selectedProvider.displayName)
        }

        lastUserMessage = userText
        streamingText   = ""
        isStreaming     = true

        contextManager.append(role: "user", content: userText)

        let stream = selectedProvider.provider.stream(
            messages:  contextManager.apiMessages(),
            system:    PromptBuilder.systemPrompt(context: context, appName: appName, screenContext: screenContext),
            apiKey:    apiKey,
            model:     selectedModel,
            maxTokens: 512
        )

        var fullResponse = ""
        do {
            for try await token in stream {
                fullResponse  += token
                streamingText  = fullResponse
            }
        } catch {
            isStreaming  = false
            lastResponse = fullResponse
            contextManager.append(role: "assistant", content: fullResponse)
            throw error
        }

        isStreaming  = false
        lastResponse = fullResponse
        contextManager.append(role: "assistant", content: fullResponse)
        return fullResponse
    }

    /// CompanionEngine-initiated proactive message.
    ///
    /// BUTLER speaks first — does NOT set `lastUserMessage` so the conversation
    /// panel doesn't show a fake "You: …" line. The response IS stored in
    /// context so the user's follow-up response has continuity.
    ///
    /// - Parameter model: Optional model override for routing (Haiku vs Sonnet).
    ///   Defaults to `selectedModel` if omitted.
    func sendProactive(
        context: ButlerContext,
        appName: String,
        screenContext: ScreenContext? = nil,
        triggerHint: String? = nil,
        model: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw SendError.noApiKey(provider: selectedProvider.displayName)
        }

        // Clear user message so panel shows only BUTLER's proactive text
        lastUserMessage = ""
        streamingText   = ""
        isStreaming     = true

        let resolvedModel = model ?? selectedModel

        let stream = selectedProvider.provider.stream(
            messages:  contextManager.apiMessages(),
            system:    PromptBuilder.proactiveSystemPrompt(context: context, appName: appName, screenContext: screenContext, triggerHint: triggerHint),
            apiKey:    apiKey,
            model:     resolvedModel,
            maxTokens: 80   // Proactive messages must be short
        )

        var fullResponse = ""
        do {
            for try await token in stream {
                fullResponse  += token
                streamingText  = fullResponse
            }
        } catch {
            isStreaming  = false
            streamingText = ""
            throw error
        }

        isStreaming  = false
        lastResponse = fullResponse
        // Store as assistant turn so follow-up conversations have continuity
        if !fullResponse.isEmpty {
            contextManager.append(role: "assistant", content: fullResponse)
        }
        return fullResponse
    }

    // MARK: - Streaming sentence path

    /// Like `send()`, but yields **complete sentences** as they arrive instead of
    /// returning the full response at the end.
    ///
    /// This is the fast path: the caller starts speaking sentence 1 while
    /// Claude is still generating sentences 2 and 3. Latency to first word
    /// drops from ~2s (full-response) to ~300ms (first sentence).
    ///
    /// Usage:
    /// ```swift
    /// for try await sentence in aiLayer.sendStreaming(text, context: ctx) {
    ///     voiceSystem.queueSentence(sentence)
    /// }
    /// await voiceSystem.drainQueue()
    /// ```
    func sendStreaming(
        _ userText: String,
        context: ButlerContext = .unknown,
        appName: String = "",
        screenContext: ScreenContext? = nil
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }

            Task { @MainActor [weak self] in
                guard let self else { continuation.finish(); return }

                guard !self.apiKey.isEmpty else {
                    self.showApiKeySetup = true
                    continuation.finish(throwing: SendError.noApiKey(provider: self.selectedProvider.displayName))
                    return
                }

                self.lastUserMessage = userText
                self.streamingText   = ""
                self.isStreaming     = true

                self.contextManager.append(role: "user", content: userText)

                let tokenStream = self.selectedProvider.provider.stream(
                    messages:  self.contextManager.apiMessages(),
                    system:    PromptBuilder.systemPrompt(context: context, appName: appName, screenContext: screenContext),
                    apiKey:    self.apiKey,
                    model:     self.selectedModel,
                    maxTokens: 512
                )

                var chunker      = SentenceChunker()
                var fullResponse = ""

                do {
                    for try await token in tokenStream {
                        guard !Task.isCancelled else { break }
                        fullResponse      += token
                        self.streamingText = fullResponse

                        // Emit any complete sentences
                        for sentence in chunker.feed(token) {
                            continuation.yield(sentence)
                        }
                    }
                    // Flush any trailing text (last partial sentence)
                    if let last = chunker.flush() {
                        continuation.yield(last)
                    }
                } catch {
                    self.isStreaming  = false
                    self.lastResponse = fullResponse
                    self.contextManager.append(role: "assistant", content: fullResponse)
                    continuation.finish(throwing: error)
                    return
                }

                self.isStreaming  = false
                self.lastResponse = fullResponse
                self.contextManager.append(role: "assistant", content: fullResponse)
                continuation.finish()
            }
        }
    }

    // MARK: - Pre-warm support

    /// Fires a speculative API call **without touching any UI state** (`isStreaming`,
    /// `streamingText`, `lastUserMessage`, `lastResponse`).
    ///
    /// Used exclusively by `CompanionEngine`'s clipboard pre-warm so that background
    /// speculative responses never cause UI flicker in the conversation panel.
    /// The result is NOT appended to the context window — call `appendAssistantResponse`
    /// if the pre-warmed response is ultimately spoken to the user.
    ///
    /// - Parameters:
    ///   - system:    Fully-built system prompt (use `PromptBuilder`).
    ///   - model:     Model identifier for this silent call.
    ///   - maxTokens: Hard cap on response length (default 80 — proactive responses are short).
    func sendSilent(system: String, model: String, maxTokens: Int = 80) async throws -> String {
        guard !apiKey.isEmpty else {
            throw SendError.noApiKey(provider: selectedProvider.displayName)
        }

        // Capture actor-isolated values before the async suspension
        let provider  = selectedProvider.provider
        let key       = apiKey
        let messages  = contextManager.apiMessages()

        let stream = provider.stream(
            messages:  messages,
            system:    system,
            apiKey:    key,
            model:     model,
            maxTokens: maxTokens
        )

        var result = ""
        for try await token in stream {
            result += token
        }
        return result
    }

    /// Appends an assistant turn to the context window and updates `lastResponse`.
    ///
    /// Used when a pre-warmed response is spoken — the context window must reflect
    /// what BUTLER said so follow-up user messages have continuity.
    func appendAssistantResponse(_ text: String) {
        guard !text.isEmpty else { return }
        contextManager.append(role: "assistant", content: text)
        lastResponse = text
    }

    /// Clears conversation history (user-triggered "forget" action).
    func clearHistory() {
        contextManager.clear()
        lastUserMessage = ""
        lastResponse    = ""
        streamingText   = ""
    }

    // MARK: - Errors

    enum SendError: Error, LocalizedError {
        case noApiKey(provider: String)

        var errorDescription: String? {
            switch self {
            case .noApiKey(let p):
                return "No API key configured for \(p). Tap ⚙ to add one."
            }
        }
    }
}

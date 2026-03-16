import Foundation

// MARK: - ModelProvider

/// Abstraction over any LLM backend.
///
/// Each provider is a stateless `Sendable` struct that knows:
///   - How to authenticate (key format, where to get one)
///   - How to stream a response (SSE parsing, message format)
///   - Which models it offers
///
/// Adding a new provider = one new file conforming to this protocol.
/// `AIIntegrationLayer` uses `any ModelProvider` and never touches
/// provider internals directly.
protocol ModelProvider: Sendable {

    /// Human-readable name shown in settings UI.
    var displayName: String { get }

    /// Default model identifier used unless the user overrides.
    var defaultModel: String { get }

    /// Available models for this provider (for a future model picker).
    var availableModels: [String] { get }

    /// Placeholder shown in the API key text field.
    var apiKeyPlaceholder: String { get }

    /// URL to the provider's key management page (shown as a link in setup UI).
    var apiKeyURL: URL { get }

    /// Whether this provider requires an API key to operate.
    /// Defaults to `true`. Local providers (Ollama) return `false`.
    var requiresApiKey: Bool { get }

    /// Open a streaming request and yield response tokens one by one.
    ///
    /// - Parameters:
    ///   - messages:  Conversation history `[["role": ..., "content": ...]]`
    ///   - system:    System prompt (providers handle this differently internally)
    ///   - apiKey:    Secret key for this provider
    ///   - model:     Model identifier (falls back to `defaultModel` if empty)
    ///   - maxTokens: Hard cap on response length
    func stream(
        messages:  [[String: String]],
        system:    String,
        apiKey:    String,
        model:     String,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - ModelProvider default implementations

extension ModelProvider {
    /// Cloud providers require a key by default.
    /// Override in local providers (e.g., `OllamaProvider`) to return `false`.
    var requiresApiKey: Bool { true }
}

// MARK: - AIProviderType

/// Enumeration of all supported providers.
///
/// Stored in `UserDefaults` so the selection persists across launches.
/// New providers are added here + a conforming struct + a Keychain account name.
enum AIProviderType: String, CaseIterable, Codable {
    case claude = "claude"
    case openai = "openai"
    case ollama = "ollama"

    // MARK: Metadata

    var displayName: String {
        switch self {
        case .claude: "Claude (Anthropic)"
        case .openai: "GPT-4 (OpenAI)"
        case .ollama: "Ollama (Local)"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .openai: "GPT-4"
        case .ollama: "Ollama"
        }
    }

    /// Keychain account identifier — one entry per cloud provider.
    /// Ollama doesn't use the Keychain (no key required).
    var keychainAccount: String {
        switch self {
        case .claude: "anthropic_api_key"
        case .openai: "openai_api_key"
        case .ollama: ""    // no-op — Ollama is local
        }
    }

    // MARK: Provider factory

    var provider: any ModelProvider {
        switch self {
        case .claude: ClaudeProvider()
        case .openai: OpenAIProvider()
        case .ollama: OllamaProvider()
        }
    }
}

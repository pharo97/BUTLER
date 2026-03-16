import Foundation

// MARK: - ContextWindowManager

/// In-memory + SQLite conversation history manager.
///
/// Keeps the last `maxMessages` turns in memory for fast API access.
/// Every turn is also persisted to SQLite via DatabaseManager so conversation
/// history survives process restarts and can be searched in future phases.
///
/// Each app launch gets a fresh `sessionID` (UUID). Turns from different
/// sessions are stored separately — Phase 3 will add cross-session retrieval.
///
/// Not an actor — accessed exclusively from ClaudeIntegrationLayer
/// which is @MainActor, so no concurrent access is possible.
final class ContextWindowManager {

    // MARK: - Configuration
    private let maxMessages: Int

    // MARK: - State
    private var messages: [(role: String, content: String)] = []

    /// Unique identifier for this app launch — groups conversation turns in SQLite.
    private let sessionID = UUID().uuidString

    init(maxMessages: Int = 20) {
        self.maxMessages = maxMessages
    }

    // MARK: - Mutations

    /// Appends a new message to the in-memory history and persists it to SQLite.
    func append(role: String, content: String) {
        messages.append((role: role, content: content))
        if messages.count > maxMessages {
            // Drop oldest messages, always keeping an even turn count
            // so we never start with an assistant message.
            messages.removeFirst(messages.count - maxMessages)
        }
        // Persist to SQLite — fire-and-forget (non-fatal on failure)
        try? DatabaseManager.shared.appendConversationTurn(
            sessionID: sessionID,
            role:      role,
            content:   content
        )
    }

    /// Removes all stored messages (user-triggered reset or session clear).
    func clear() {
        messages.removeAll()
        try? DatabaseManager.shared.clearConversation(sessionID: sessionID)
    }

    // MARK: - Queries

    /// Returns the conversation history formatted for the Claude API.
    func apiMessages() -> [[String: String]] {
        messages.map { ["role": $0.role, "content": $0.content] }
    }

    /// Returns the most recent user message, or nil if history is empty.
    var lastUserMessage: String? {
        messages.last(where: { $0.role == "user" })?.content
    }

    /// Number of turns (user + assistant messages) in history.
    var turnCount: Int { messages.count }
}

import Foundation
import GRDB

// MARK: - DatabaseManager

/// Central SQLite database for BUTLER's persistent state.
///
/// Owns three tables:
///   • `tolerance_models`   — Bayesian alpha/beta for each ButlerContext
///   • `conversation_turns` — Full conversation history, keyed by session ID
///   • `librarian_signals`  — Context signals from IdleBackgroundProcessor (filenames only)
///
/// Uses GRDB's `DatabaseQueue` which is thread-safe and Sendable.
/// Marked `@unchecked Sendable` because `DatabaseQueue` handles its own
/// internal serialization — no external locking is required.
///
/// All write operations are synchronous but complete in microseconds for the
/// small payloads we're storing (tolerance floats + conversation text).
///
/// Usage:
/// ```swift
/// let db = DatabaseManager.shared
/// try? db.saveTolerance(contextID: "coding", alpha: 3.0, beta: 2.0)
/// ```
final class DatabaseManager: @unchecked Sendable {

    // MARK: - Shared singleton

    static let shared = DatabaseManager()

    // MARK: - Internals

    private var dbQueue: DatabaseQueue?

    // MARK: - Init

    private init() {
        do {
            let url  = try Self.databaseURL()
            let queue = try DatabaseQueue(path: url.path)
            try Self.createTables(in: queue)
            dbQueue  = queue
            print("[DatabaseManager] Opened at \(url.lastPathComponent)")
        } catch {
            // Non-fatal: app continues without persistence.
            print("[DatabaseManager] Failed to open: \(error)")
        }
    }

    // MARK: - Setup

    private static func databaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for:                  .applicationSupportDirectory,
            in:                   .userDomainMask,
            appropriateFor:       nil,
            create:               true
        )
        let dir = appSupport.appendingPathComponent("Butler", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("butler.db")
    }

    private static func createTables(in queue: DatabaseQueue) throws {
        try queue.write { db in

            // Bayesian tolerance models (one row per ButlerContext.rawValue)
            try db.create(table: "tolerance_models", ifNotExists: true) { t in
                t.primaryKey("context_id", .text)
                t.column("alpha",        .double).notNull().defaults(to: 2.0)
                t.column("beta",         .double).notNull().defaults(to: 2.0)
                t.column("last_updated", .integer).notNull()
            }

            // Full conversation history (one row per message turn)
            try db.create(table: "conversation_turns", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id",  .text).notNull().indexed()
                t.column("role",        .text).notNull()   // "user" | "assistant"
                t.column("content",     .text).notNull()
                t.column("timestamp",   .integer).notNull()
                t.column("app_context", .text)              // nullable: active ButlerContext
            }

            // Librarian signals: context inferred from file metadata (filenames only).
            // Source summaries contain only filenames — never file content.
            try db.create(table: "librarian_signals", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("signal_type",     .text).notNull()     // LibrarianSignal.SignalType.rawValue
                t.column("context_hint",    .text).notNull()     // ButlerContext.rawValue
                t.column("weight",          .double).notNull()
                t.column("source_summary",  .text).notNull()     // filename only
                t.column("timestamp",       .integer).notNull()
            }
        }
    }

    // MARK: - Tolerance CRUD

    /// Upsert a tolerance model for `contextID`.
    func saveTolerance(contextID: String, alpha: Double, beta: Double) throws {
        try dbQueue?.write { db in
            try db.execute(sql: """
                INSERT INTO tolerance_models (context_id, alpha, beta, last_updated)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(context_id) DO UPDATE SET
                    alpha        = excluded.alpha,
                    beta         = excluded.beta,
                    last_updated = excluded.last_updated
            """, arguments: [contextID, alpha, beta, Int(Date().timeIntervalSince1970)])
        }
    }

    /// Returns all persisted tolerance records as a dictionary keyed by context_id.
    func loadToleranceModels() throws -> [String: ToleranceRecord] {
        guard let queue = dbQueue else { return [:] }
        return try queue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM tolerance_models")
            var dict: [String: ToleranceRecord] = [:]
            for row in rows {
                let rec = ToleranceRecord(
                    contextID:   row["context_id"],
                    alpha:       row["alpha"],
                    beta:        row["beta"],
                    lastUpdated: Date(timeIntervalSince1970: TimeInterval(row["last_updated"] as Int))
                )
                dict[rec.contextID] = rec
            }
            return dict
        }
    }

    // MARK: - Conversation CRUD

    /// Appends a single message turn to the conversation history.
    func appendConversationTurn(
        sessionID:  String,
        role:       String,
        content:    String,
        appContext: String? = nil
    ) throws {
        try dbQueue?.write { db in
            try db.execute(sql: """
                INSERT INTO conversation_turns
                    (session_id, role, content, timestamp, app_context)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                sessionID,
                role,
                content,
                Int(Date().timeIntervalSince1970),
                appContext
            ])
        }
    }

    /// Loads the most recent `limit` turns for `sessionID`, in chronological order.
    func loadConversationTurns(
        sessionID: String,
        limit:     Int = 20
    ) throws -> [(role: String, content: String)] {
        guard let queue = dbQueue else { return [] }
        return try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT role, content
                FROM conversation_turns
                WHERE session_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
            """, arguments: [sessionID, limit])
            // Reverse so oldest message is first (chronological order for API)
            return rows.reversed().map { (role: $0["role"], content: $0["content"]) }
        }
    }

    /// Deletes all turns for a given session (e.g. on conversation clear).
    func clearConversation(sessionID: String) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql:       "DELETE FROM conversation_turns WHERE session_id = ?",
                arguments: [sessionID]
            )
        }
    }

    // MARK: - Librarian signal CRUD

    /// Inserts a single librarian signal. `source_summary` must contain filename only.
    func saveLibrarianSignal(_ signal: LibrarianSignal) throws {
        try dbQueue?.write { db in
            try db.execute(sql: """
                INSERT INTO librarian_signals
                    (signal_type, context_hint, weight, source_summary, timestamp)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                signal.type.rawValue,
                signal.contextHint.rawValue,
                signal.weight,
                signal.sourceSummary,
                Int(signal.timestamp.timeIntervalSince1970)
            ])
        }
    }

    /// Returns aggregated context weights from librarian signals.
    ///
    /// Sums `weight` per `context_hint` — callers use this to understand which
    /// contexts the user has been active in recently.
    ///
    /// - Parameter days: Only include signals from the past N days.
    func librarianContextWeights(withinDays days: Int = 7) throws -> [String: Double] {
        guard let queue = dbQueue else { return [:] }
        let cutoff = Int(Date().addingTimeInterval(-Double(days) * 86_400)
            .timeIntervalSince1970)

        return try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT context_hint, SUM(weight) AS total_weight
                FROM librarian_signals
                WHERE timestamp >= ?
                GROUP BY context_hint
                ORDER BY total_weight DESC
            """, arguments: [cutoff])

            var result: [String: Double] = [:]
            for row in rows {
                result[row["context_hint"]] = row["total_weight"]
            }
            return result
        }
    }

    /// Deletes signals older than `days` days to keep the DB lean.
    func pruneLibrarianSignals(olderThanDays days: Int) throws {
        let cutoff = Int(Date().addingTimeInterval(-Double(days) * 86_400)
            .timeIntervalSince1970)
        try dbQueue?.write { db in
            try db.execute(
                sql:       "DELETE FROM librarian_signals WHERE timestamp < ?",
                arguments: [cutoff]
            )
        }
    }

    /// Total number of librarian signals stored (for debug overlay).
    func librarianSignalCount() throws -> Int {
        guard let queue = dbQueue else { return 0 }
        return try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM librarian_signals") ?? 0
        }
    }
}

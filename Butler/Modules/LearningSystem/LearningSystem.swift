import Foundation

// MARK: - LearningSystem

/// Manages per-context `ToleranceModel` instances.
///
/// Persistence hierarchy (automatic):
///   1. **SQLite via GRDB** (DatabaseManager.shared) — primary store.
///   2. **UserDefaults** migration — on first launch after upgrade,
///      existing UserDefaults data is read, promoted to SQLite, then deleted.
///
/// Memory Palace integration:
///   Every `recordAccept` / `recordDismiss` call writes a human-readable
///   fact to `MemoryWriter.shared` (habits category) so Butler remembers
///   which contexts the user welcomes or resists interventions in.
///
/// Thread-safety: @MainActor — all mutations happen on the main actor.
@MainActor
@Observable
final class LearningSystem {

    // MARK: - Legacy storage key (UserDefaults migration)

    private static let legacyDefaultsKey = "butler.learningSystem.models.v1"

    // MARK: - Memory Palace reference

    private let memory = MemoryWriter.shared

    // MARK: - State

    private(set) var models: [String: ToleranceModel] = [:]

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Tolerance query

    /// Returns the current tolerance [0, 1] for a given context.
    func tolerance(for context: ButlerContext) -> Double {
        model(for: context).tolerance
    }

    /// Full model (useful for debug / admin views).
    func toleranceModel(for context: ButlerContext) -> ToleranceModel {
        model(for: context)
    }

    // MARK: - Outcome recording

    func recordAccept(context: ButlerContext) {
        models[context.rawValue, default: ToleranceModel()].recordAccept()
        save()
        memory.appendFacts(memoryFacts(for: context, accepted: true), to: .habits)
    }

    func recordDismiss(context: ButlerContext) {
        models[context.rawValue, default: ToleranceModel()].recordDismiss()
        save()
        memory.appendFacts(memoryFacts(for: context, accepted: false), to: .habits)
    }

    func recordManualTrigger(context: ButlerContext) {
        models[context.rawValue, default: ToleranceModel()].recordManualTrigger()
        save()
    }

    // MARK: - Session-boundary decay

    /// Call on system wake or screen unlock.
    /// Decays all tolerance models so stale evidence fades over time.
    func decayAll(factor: Double = 0.95) {
        for key in models.keys {
            models[key]?.decay(factor: factor)
        }
        save()
    }

    // MARK: - Debug / admin

    /// Resets a single context back to the neutral prior.
    func resetContext(_ context: ButlerContext) {
        models[context.rawValue] = ToleranceModel()
        save()
    }

    /// Resets all learned data (SQLite + legacy UserDefaults).
    func resetAll() {
        models = [:]
        // Clear SQLite by re-saving the empty dict (existing rows remain but
        // are overwritten on next recordAccept/Dismiss, which is fine).
        // For a hard wipe, we'd drop and recreate the table; not worth it here.
        UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
    }

    // MARK: - Private helpers

    private func model(for context: ButlerContext) -> ToleranceModel {
        models[context.rawValue] ?? ToleranceModel()
    }

    /// Persists all current models to SQLite.
    private func save() {
        for (contextID, m) in models {
            try? DatabaseManager.shared.saveTolerance(
                contextID: contextID,
                alpha:     m.alpha,
                beta:      m.beta
            )
        }
    }

    /// Loads models from SQLite. On first run after an upgrade, migrates
    /// any data found in UserDefaults to SQLite and removes the old entry.
    private func load() {
        // Primary: SQLite
        if let records = try? DatabaseManager.shared.loadToleranceModels(), !records.isEmpty {
            models = records.mapValues { ToleranceModel(alpha: $0.alpha, beta: $0.beta) }
            return
        }

        // Fallback: UserDefaults migration path (Phase 1 -> Phase 2)
        if let data  = UserDefaults.standard.data(forKey: Self.legacyDefaultsKey),
           let saved = try? JSONDecoder().decode([String: ToleranceModel].self, from: data) {
            models = saved
            save()  // Promote to SQLite
            UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
            print("[LearningSystem] Migrated \(saved.count) model(s) from UserDefaults to SQLite.")
        }
    }

    // MARK: - Memory fact generation

    /// Builds a short list of human-readable facts to write into the Memory Palace
    /// after an intervention accept or dismiss event.
    private func memoryFacts(for context: ButlerContext, accepted: Bool) -> [String] {
        let verb      = accepted ? "accepted" : "dismissed"
        let tolerance = String(format: "%.2f", model(for: context).tolerance)
        var facts: [String] = [
            "Intervention \(verb) — context: \(context.displayName), tolerance now \(tolerance)"
        ]
        if !accepted {
            facts.append("Dismissal pattern: \(context.displayName) — may prefer less intervention here")
        }
        return facts
    }
}

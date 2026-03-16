import Foundation

// MARK: - ToleranceRecord

/// Plain value type returned by `DatabaseManager.loadToleranceModels()`.
///
/// Carries the Bayesian alpha/beta pair for one `ButlerContext`,
/// plus the timestamp of the last write (useful for future decay logic).
struct ToleranceRecord {

    /// Raw value of `ButlerContext` (e.g. "coding", "writing").
    let contextID:   String

    /// Bayesian alpha — positive evidence. Starts at 2.0.
    var alpha:       Double

    /// Bayesian beta — negative evidence. Starts at 2.0.
    var beta:        Double

    /// When this record was last persisted.
    var lastUpdated: Date

    /// Derived tolerance in [0, 1].  α/(α+β)
    var tolerance: Double { alpha / (alpha + beta) }
}

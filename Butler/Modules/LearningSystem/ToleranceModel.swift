import Foundation

// MARK: - ToleranceModel

/// Bayesian Beta-distribution model of user tolerance for BUTLER interventions.
///
/// tolerance = α / (α + β)
///
/// Updates:
///   • accept         → α += 1.0   (positive evidence)
///   • dismiss        → β += 2.0   (stronger negative — friction matters more)
///   • manual trigger → α += 0.5   (softer positive — user initiated, not BUTLER)
///
/// Decay (call on system wake):
///   • Both α and β multiplied by `factor` (default 0.95)
///   • Floored at 1.0 — never collapses the prior
///
/// Initial values α=2, β=2 give tolerance = 0.50 (neutral prior).
struct ToleranceModel: Codable {

    // MARK: - Parameters

    var alpha: Double   // positive evidence accumulator
    var beta:  Double   // negative evidence accumulator

    // MARK: - Init

    init(alpha: Double = 2.0, beta: Double = 2.0) {
        self.alpha = alpha
        self.beta  = beta
    }

    // MARK: - Computed metric

    /// Normalized tolerance [0, 1]. Values ≥ 0.65 allow BUTLER to intervene.
    var tolerance: Double {
        alpha / (alpha + beta)
    }

    // MARK: - Signal updates

    /// User engaged with / accepted an intervention.
    mutating func recordAccept() {
        alpha += 1.0
    }

    /// User dismissed or ignored an intervention.
    mutating func recordDismiss() {
        beta += 2.0  // asymmetric: dismissals outweigh accepts 2:1
    }

    /// User proactively triggered BUTLER (mic tap, hotkey…).
    mutating func recordManualTrigger() {
        alpha += 0.5  // smaller — they called BUTLER, not the other way around
    }

    // MARK: - Session-boundary decay

    /// Leaky-bucket decay applied on system wake / screen unlock.
    /// Old evidence matters less over time — tolerance drifts toward 0.50.
    mutating func decay(factor: Double = 0.95) {
        alpha = max(1.0, alpha * factor)
        beta  = max(1.0, beta  * factor)
    }

    // MARK: - Debug

    var description: String {
        String(
            format: "ToleranceModel(α=%.2f β=%.2f → %.0f%%)",
            alpha, beta, tolerance * 100
        )
    }
}

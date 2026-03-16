import Foundation

// MARK: - InterventionEngine

/// Decides whether BUTLER should proactively intervene at this moment.
///
/// Score formula:
///   InterventionScore = contextWeight × tolerance × timeModifier × frequencyDecay
///
/// Fires when score ≥ 0.65 AND no hard kill-switch is active.
///
/// Hard limits (always enforced):
///   • Max 3 interventions per rolling 60-minute window
///   • Min 3 minutes between any two interventions
///   • Zero-weight contexts (videoCall) always suppressed
@MainActor
@Observable
final class InterventionEngine {

    // MARK: - Tuning constants

    static let scoreThreshold:    Double = 0.65
    static let maxPerHour:        Int    = 3
    static let minGapSeconds:     Double = 180    // 3 minutes
    static let rollingWindowSecs: Double = 3_600  // 1 hour
    static let rampUpSeconds:     Double = 600    // 10 minutes for full time-modifier

    // MARK: - State

    private(set) var lastInterventionAt: Date?
    private(set) var interventionsThisHour: Int = 0

    private var interventionLog: [Date] = []

    // MARK: - Dependencies

    private let learningSystem:     LearningSystem
    private let permissionSecurity: PermissionSecurityManager
    private let rhythmTracker:      DailyRhythmTracker

    // MARK: - Init

    init(
        learningSystem:     LearningSystem,
        permissionSecurity: PermissionSecurityManager,
        rhythmTracker:      DailyRhythmTracker
    ) {
        self.learningSystem     = learningSystem
        self.permissionSecurity = permissionSecurity
        self.rhythmTracker      = rhythmTracker
    }

    // MARK: - Decision API

    /// Returns `true` if BUTLER should proactively speak up right now.
    func shouldIntervene(context: ButlerContext) -> Bool {
        // 1. Kill switches
        guard !permissionSecurity.checkSuppression() else { return false }

        // 2. Frequency cap
        pruneLog()
        guard interventionLog.count < Self.maxPerHour else { return false }

        // 3. Minimum gap
        if let last = lastInterventionAt,
           Date().timeIntervalSince(last) < Self.minGapSeconds {
            return false
        }

        // 4. Score threshold
        return interventionScore(for: context) >= Self.scoreThreshold
    }

    /// `true` if the hard rate limits (hourly cap or min gap) are currently blocking.
    /// Used by high-priority triggers (clipboard, calendar) that bypass score threshold.
    func isHardRateLimited() -> Bool {
        // Kill switches still apply
        guard !permissionSecurity.checkSuppression() else { return true }

        pruneLog()
        if interventionLog.count >= Self.maxPerHour { return true }
        if let last = lastInterventionAt,
           Date().timeIntervalSince(last) < Self.minGapSeconds { return true }
        return false
    }

    /// Full numeric score [0, 1] — useful for debugging and admin overlays.
    ///
    /// Formula: contextWeight × tolerance × timeModifier × frequencyDecay × rhythmMultiplier
    func interventionScore(for context: ButlerContext) -> Double {
        let cw = contextWeight(for: context)
        guard cw > 0 else { return 0 }

        let tol   = learningSystem.tolerance(for: context)
        let timem = timeModifier()
        let freqd = frequencyDecay()
        let rhythm = min(1.0, rhythmTracker.rhythmMultiplier)  // cap at 1.0 so rhythm boosts are modest

        return cw * tol * timem * freqd * rhythm
    }

    // MARK: - Outcome recording

    /// Call immediately after BUTLER fires an intervention.
    func recordInterventionFired() {
        let now = Date()
        lastInterventionAt = now
        interventionLog.append(now)
        pruneLog()
        interventionsThisHour = interventionLog.count
    }

    /// Call when user engages with / accepts a proactive suggestion.
    func recordAccepted(context: ButlerContext) {
        learningSystem.recordAccept(context: context)
    }

    /// Call when user dismisses / ignores a proactive suggestion.
    func recordDismissed(context: ButlerContext) {
        learningSystem.recordDismiss(context: context)
    }

    /// Call when user proactively taps mic (strong positive signal).
    func recordManualTrigger(context: ButlerContext) {
        learningSystem.recordManualTrigger(context: context)
    }

    // MARK: - Private scoring helpers

    /// How intrinsically valuable is an intervention in this context?
    /// videoCall = 0 acts as a hard zero regardless of other factors.
    private func contextWeight(for context: ButlerContext) -> Double {
        switch context {
        case .coding:       0.90
        case .writing:      0.85
        case .browsing:     0.70
        case .productivity: 0.75
        case .comms:        0.60
        case .creative:     0.55
        case .unknown:      0.40
        case .videoCall:    0.00  // always zero — never interrupt a call
        }
    }

    /// Ramps from 0 → 1 over `rampUpSeconds` since the last intervention.
    /// Prevents bursting — BUTLER waits before speaking again.
    private func timeModifier() -> Double {
        guard let last = lastInterventionAt else { return 1.0 }
        let elapsed = Date().timeIntervalSince(last)
        return min(1.0, elapsed / Self.rampUpSeconds)
    }

    /// Decreases as the rolling count approaches the hourly cap.
    private func frequencyDecay() -> Double {
        pruneLog()
        let used = Double(interventionLog.count)
        let cap  = Double(Self.maxPerHour)
        return max(0.0, 1.0 - (used / cap))
    }

    /// Drops log entries older than the rolling window.
    private func pruneLog() {
        let cutoff = Date().addingTimeInterval(-Self.rollingWindowSecs)
        interventionLog.removeAll { $0 < cutoff }
        interventionsThisHour = interventionLog.count
    }
}

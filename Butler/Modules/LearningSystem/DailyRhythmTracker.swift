import Foundation

// MARK: - DailyRhythmTracker

/// Learns the user's daily engagement rhythm to help BUTLER pick better moments to speak.
///
/// Records a signal each time the user manually triggers BUTLER or accepts a proactive
/// suggestion. Over time this builds a per-hour engagement profile (an exponential
/// moving average) that adds a small multiplier to the intervention score during the
/// user's peak hours and dampens it during historically quiet windows.
///
/// ## Model
///
/// Each hour-of-day (0–23) has an engagement score in [0, 1]:
///   - 0.5 = neutral prior (no data yet)
///   - > 0.5 = user is historically more engaged at this hour → BUTLER more likely to speak
///   - < 0.5 = user is historically quieter → BUTLER backs off
///
/// Update rule (EMA):
///   `score[h] = score[h] * (1 - α) + signal * α`   where α = learnRate
///
/// Signal weights:
///   - Manual trigger: 1.0 (strongest positive — user explicitly wanted BUTLER)
///   - Accept:         0.7 (positive — BUTLER was welcome at this time)
///   - Dismiss:        0.1 (negative signal — user found it unwelcome; BUTLER backs off)
///
/// The tracker also contributes a `rhythmMultiplier` [0.6, 1.4] used by
/// `InterventionEngine` as an additional scoring factor.
///
/// Persistence: UserDefaults (small dict, no schema needed).
@MainActor
@Observable
final class DailyRhythmTracker {

    // MARK: - Configuration

    private let learnRate:      Double = 0.12   // EMA alpha — how fast to learn
    private let defaultsKey             = "butler.rhythm.hourlyEngagement.v1"

    // MARK: - State

    /// Per-hour engagement score (0-indexed, 0 = midnight).
    private(set) var hourlyEngagement: [Int: Double] = [:]

    // MARK: - Init

    init() { load() }

    // MARK: - Signal recording

    /// Call when the user manually presses the mic button (strongest positive signal).
    func recordManualTrigger() {
        update(signal: 1.0)
        save()
    }

    /// Call when the user accepts a proactive suggestion.
    func recordAccept() {
        update(signal: 0.7)
        save()
    }

    /// Call when the user dismisses a proactive suggestion.
    func recordDismiss() {
        update(signal: 0.1)
        save()
    }

    // MARK: - Rhythm query

    /// Raw engagement score for a given hour-of-day [0, 1].
    /// Returns 0.5 (neutral prior) for hours with no data.
    func engagementScore(hour: Int) -> Double {
        hourlyEngagement[hour] ?? 0.5
    }

    /// Engagement score for the current wall-clock hour.
    var currentEngagementScore: Double {
        engagementScore(hour: currentHour)
    }

    /// Multiplier for use in `InterventionEngine` scoring.
    /// Maps [0, 1] engagement → [0.6, 1.4] so BUTLER is up to 40% more
    /// likely during peak hours and 40% less likely during quiet windows.
    var rhythmMultiplier: Double {
        let score = currentEngagementScore  // [0, 1]
        return 0.6 + score * 0.8           // linear map: 0→0.6, 0.5→1.0, 1→1.4
    }

    // MARK: - Session-boundary decay

    /// Call on system wake. Lets engagement drift back toward neutral (0.5) over
    /// time so stale patterns don't lock in BUTLER's behaviour permanently.
    func decayAll(factor: Double = 0.97) {
        for hour in hourlyEngagement.keys {
            let v = hourlyEngagement[hour] ?? 0.5
            hourlyEngagement[hour] = 0.5 + (v - 0.5) * factor
        }
        save()
    }

    // MARK: - Private

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private func update(signal: Double) {
        let hour = currentHour
        let prev = hourlyEngagement[hour] ?? 0.5
        hourlyEngagement[hour] = prev * (1 - learnRate) + signal * learnRate
    }

    private func save() {
        // Encode as [String: Double] since UserDefaults can't store [Int: Double] directly.
        let encoded = Dictionary(uniqueKeysWithValues:
            hourlyEngagement.map { ("\($0.key)", $0.value) }
        )
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double]
        else { return }
        hourlyEngagement = Dictionary(uniqueKeysWithValues:
            dict.compactMap { k, v in Int(k).map { ($0, v) } }
        )
    }
}

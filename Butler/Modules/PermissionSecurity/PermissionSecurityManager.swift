import Foundation

// MARK: - PermissionSecurityManager

/// Kill-switch layer that prevents BUTLER from interrupting the user
/// at inappropriate moments.
///
/// Suppression triggers (any one is enough to silence BUTLER):
///   • Active video call (Zoom, Teams, FaceTime, etc.)
///   • Active screen share
///   • Fullscreen app (games, Keynote presentation, etc.)
///
/// Phase 2 additions (not yet wired):
///   • macOS Focus / Do Not Disturb mode
///   • User-defined quiet hours
@MainActor
@Observable
final class PermissionSecurityManager {

    // MARK: - Published state

    /// True when at least one suppression condition is active.
    var isSuppressed:     Bool    = false

    /// Human-readable reason for the current suppression (first trigger wins).
    var suppressionReason: String? = nil

    // MARK: - Dependency

    private let activityMonitor: ActivityMonitor

    // MARK: - Init

    init(activityMonitor: ActivityMonitor) {
        self.activityMonitor = activityMonitor
    }

    // MARK: - Suppression check

    /// Evaluates all kill switches and updates `isSuppressed` / `suppressionReason`.
    /// Returns `true` if BUTLER should stay silent.
    @discardableResult
    func checkSuppression() -> Bool {
        var reasons: [String] = []

        if activityMonitor.isVideoCall {
            reasons.append("on a call")
        }
        if activityMonitor.isScreenSharing {
            reasons.append("screen sharing active")
        }
        if activityMonitor.isFullscreen {
            reasons.append("fullscreen app")
        }

        isSuppressed      = !reasons.isEmpty
        suppressionReason = reasons.first
        return isSuppressed
    }

    // MARK: - Convenience

    /// Returns true without side-effects — use for read-only checks.
    var suppressedNow: Bool {
        activityMonitor.isVideoCall ||
        activityMonitor.isScreenSharing ||
        activityMonitor.isFullscreen
    }
}

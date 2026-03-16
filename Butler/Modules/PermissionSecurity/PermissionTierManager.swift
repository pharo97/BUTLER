import Foundation

// MARK: - PermissionTierManager

/// Tracks which capability tiers the user has explicitly opted into.
///
/// BUTLER defaults to the lowest capability tier (Passive) and requires
/// deliberate user action to unlock higher-capability tiers. This design
/// ensures the user always understands what BUTLER can and cannot do.
///
/// ## Tiers
///
/// **Tier 0 — Passive** *(always active, no toggle)*
///   Activity monitoring: which app is frontmost, rough context classification.
///   Nothing is read from screen or clipboard. No voice unless user initiates.
///
/// **Tier 1 — App Awareness** *(default: OFF)*
///   Screen context reading + clipboard monitoring.
///   Butler can see what text is on screen and react to clipboard changes.
///
/// **Tier 2 — Interventions** *(default: OFF)*
///   Proactive voice suggestions without the user pressing the mic button.
///   Requires Tier 1 to be most effective.
///
/// **Tier 3 — Automation** *(default: OFF, locked in Phase 1)*
///   File operations, AppleScript, Shortcuts integration.
///   Not yet available — displayed as "coming soon" in UI.
///
/// **Tier 4 — Librarian** *(default: OFF)*
///   Background idle scanning of file metadata (filenames + extensions only).
///   Builds context awareness without reading any file content.
///   Sub-permissions: Downloads scan, Desktop scan, clipboard pattern detection.
///
/// Tier state is persisted to `UserDefaults` and restored on launch.
@MainActor
@Observable
final class PermissionTierManager {

    // MARK: - UserDefaults keys

    private enum Keys {
        static let tier1 = "butler.perm.tier1Enabled"
        static let tier2 = "butler.perm.tier2Enabled"
        static let tier3 = "butler.perm.tier3Enabled"
        static let tier4 = "butler.perm.tier4Enabled"
        // Tier 4 sub-permissions
        static let tier4Downloads = "butler.perm.tier4Downloads"
        static let tier4Desktop   = "butler.perm.tier4Desktop"
        static let tier4Clipboard = "butler.perm.tier4Clipboard"
    }

    // MARK: - Tier state

    /// Tier 1: Screen context + clipboard monitoring.
    var tier1Enabled: Bool = false {
        didSet { UserDefaults.standard.set(tier1Enabled, forKey: Keys.tier1) }
    }

    /// Tier 2: Proactive voice interventions.
    var tier2Enabled: Bool = false {
        didSet { UserDefaults.standard.set(tier2Enabled, forKey: Keys.tier2) }
    }

    /// Tier 3: Automation (Phase 3 — not yet available).
    var tier3Enabled: Bool = false {
        didSet { UserDefaults.standard.set(tier3Enabled, forKey: Keys.tier3) }
    }

    /// Tier 4: Librarian background scanning (opt-in).
    /// Toggling this off stops the IdleBackgroundProcessor immediately.
    var tier4Enabled: Bool = false {
        didSet { UserDefaults.standard.set(tier4Enabled, forKey: Keys.tier4)
                 if !tier4Enabled { tier4Downloads = false; tier4Desktop = false; tier4Clipboard = false }
        }
    }

    // MARK: - Tier 4 sub-permissions

    /// Scan ~/Downloads for recently added files (filenames only).
    var tier4Downloads: Bool = false {
        didSet { UserDefaults.standard.set(tier4Downloads, forKey: Keys.tier4Downloads) }
    }

    /// Scan ~/Desktop for project files (filenames only).
    var tier4Desktop: Bool = false {
        didSet { UserDefaults.standard.set(tier4Desktop, forKey: Keys.tier4Desktop) }
    }

    /// Detect code/text patterns in current clipboard (no clipboard history stored).
    var tier4Clipboard: Bool = false {
        didSet { UserDefaults.standard.set(tier4Clipboard, forKey: Keys.tier4Clipboard) }
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        tier1Enabled   = d.bool(forKey: Keys.tier1)
        tier2Enabled   = d.bool(forKey: Keys.tier2)
        tier3Enabled   = d.bool(forKey: Keys.tier3)
        tier4Enabled   = d.bool(forKey: Keys.tier4)
        tier4Downloads = d.bool(forKey: Keys.tier4Downloads)
        tier4Desktop   = d.bool(forKey: Keys.tier4Desktop)
        tier4Clipboard = d.bool(forKey: Keys.tier4Clipboard)
    }
}

import AppKit
import CoreGraphics
import Foundation

// MARK: - ButlerContext

/// Semantic context BUTLER infers from the user's frontmost application.
/// Used to weight intervention scores and personalize system prompts.
enum ButlerContext: String, CaseIterable, Codable {
    case unknown      = "unknown"
    case coding       = "coding"        // Xcode, VSCode, Terminal…
    case writing      = "writing"       // Notes, Word, Pages, Obsidian…
    case browsing     = "browsing"      // Safari, Chrome, Firefox…
    case comms        = "comms"         // Slack, Mail, Messages…
    case videoCall    = "video_call"    // Zoom, Teams, Meet, FaceTime…
    case creative     = "creative"      // Figma, Sketch, Photoshop…
    case productivity = "productivity"  // Excel, Numbers, Calendar…

    var displayName: String {
        switch self {
        case .unknown:      "Idle"
        case .coding:       "Coding"
        case .writing:      "Writing"
        case .browsing:     "Browsing"
        case .comms:        "Communicating"
        case .videoCall:    "On a call"
        case .creative:     "Creating"
        case .productivity: "Working"
        }
    }

    /// Short label for the Glass Chamber context badge.
    var badge: String {
        switch self {
        case .unknown:      ""
        case .coding:       "{ }"
        case .writing:      "✍︎"
        case .browsing:     "◉"
        case .comms:        "◎"
        case .videoCall:    "▶"
        case .creative:     "✦"
        case .productivity: "⊞"
        }
    }
}

// MARK: - ActivityMonitor

/// Watches NSWorkspace for active-app changes and classifies user context.
///
/// Also polls (every 5 s) for screen-sharing and fullscreen state —
/// both are kill-switch signals that suppress BUTLER interventions.
@MainActor
@Observable
final class ActivityMonitor {

    // MARK: - Published state

    var frontmostBundleID: String   = ""
    var frontmostAppName:  String   = ""
    var context:           ButlerContext = .unknown
    var isVideoCall:       Bool     = false
    var isScreenSharing:   Bool     = false
    var isFullscreen:      Bool     = false

    // MARK: - Private

    private var workspaceObserver: (any NSObjectProtocol)?
    private var pollTask:          Task<Void, Never>?

    // MARK: - Known bundle ID sets (classified by context)

    private static let videoCallApps: Set<String> = [
        "us.zoom.xos",                   // Zoom
        "com.microsoft.teams",           // Teams
        "com.apple.FaceTime",            // FaceTime
        "com.loom.desktop",              // Loom
        "com.webex.meetingmanager",      // Webex
        "com.whereby.app",               // Whereby
        "com.discord.mac",               // Discord (voice/video)
    ]

    private static let codingApps: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.jetbrains.AppCode",
        "com.sublimetext.4",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.todesktop.230313mzl4w4u92", // Cursor
    ]

    private static let writingApps: Set<String> = [
        "com.apple.Notes",
        "com.apple.TextEdit",
        "com.microsoft.Word",
        "com.apple.iWork.Pages",
        "md.obsidian",
        "com.notion.id",
        "net.shinyfrog.bear",
        "io.typora.typora",
        "com.ulyssesapp.mac",
    ]

    private static let browsingApps: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "company.thebrowser.Browser", // Arc
    ]

    private static let commsApps: Set<String> = [
        "com.tinyspeck.slackmacgap",   // Slack
        "com.apple.mail",
        "com.apple.MobileSMS",         // Messages
        "com.microsoft.Outlook",
        "com.superhuman.Superhuman",
        "com.discord.mac",
        "com.telegram.Telegram",
    ]

    private static let creativeApps: Set<String> = [
        "com.figma.Desktop",
        "com.bohemiancoding.sketch3",
        "com.adobe.Photoshop",
        "com.adobe.illustrator",
        "com.adobe.AfterEffects",
        "com.apple.FinalCut",
        "com.apple.Logic-Pro",
    ]

    private static let productivityApps: Set<String> = [
        "com.microsoft.Excel",
        "com.apple.iWork.Numbers",
        "com.apple.iCal",
        "com.apple.Reminders",
        "com.culturedcode.ThingsMac",  // Things 3
        "com.agiletortoise.Drafts-OSX",
        "com.omnigroup.OmniFocus3",
        "com.linear.linear",
    ]

    // MARK: - Lifecycle

    func start() {
        // Observe frontmost app switches on main queue
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateFrontmostApp() }
        }

        // Poll slow-changing state every 5 seconds
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSystemState()
                try? await Task.sleep(for: .seconds(5))
            }
        }

        // Snapshot current state immediately
        updateFrontmostApp()
    }

    func stop() {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        pollTask?.cancel()
    }

    // MARK: - Private helpers

    private func updateFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        frontmostBundleID = app.bundleIdentifier ?? ""
        frontmostAppName  = app.localizedName ?? ""
        context           = classify(bundleID: frontmostBundleID)
        isVideoCall       = Self.videoCallApps.contains(frontmostBundleID)
    }

    @MainActor
    private func pollSystemState() {
        isScreenSharing = detectScreenSharing()
        if let app = NSWorkspace.shared.frontmostApplication {
            isFullscreen = detectFullscreen(for: app)
        }
    }

    /// Heuristic: look for known screen-sharing helper processes.
    private func detectScreenSharing() -> Bool {
        let sharingIndicators = ["screensharingd", "legacyScreenSharingAgent"]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let name = app.localizedName else { return false }
            return sharingIndicators.contains { name.contains($0) }
        }
    }

    /// Checks if the frontmost app's window covers the full main screen.
    /// Requires Screen Recording permission — gracefully returns false if denied.
    private func detectFullscreen(for app: NSRunningApplication) -> Bool {
        guard let screen = NSScreen.main else { return false }

        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] ?? []

        return windowList.contains { info in
            guard
                let pid = info[kCGWindowOwnerPID] as? Int32,
                pid == app.processIdentifier,
                let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                let w = bounds["Width"], let h = bounds["Height"]
            else { return false }

            let sf = screen.frame
            return w >= sf.width && h >= sf.height
        }
    }

    private func classify(bundleID: String) -> ButlerContext {
        if Self.videoCallApps.contains(bundleID)    { return .videoCall }
        if Self.codingApps.contains(bundleID)       { return .coding }
        if Self.writingApps.contains(bundleID)      { return .writing }
        if Self.browsingApps.contains(bundleID)     { return .browsing }
        if Self.commsApps.contains(bundleID)        { return .comms }
        if Self.creativeApps.contains(bundleID)     { return .creative }
        if Self.productivityApps.contains(bundleID) { return .productivity }
        return .unknown
    }
}

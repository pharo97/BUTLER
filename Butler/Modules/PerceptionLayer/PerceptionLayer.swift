import Foundation
import AppKit

// MARK: - PerceptionLayer

/// Single facade that wraps all ambient sensing:
///   • Browser URL + selected text via `ScreenContextReader`
///   • Clipboard changes via `ClipboardMonitor`
///   • Upcoming calendar events via `CalendarBridge`
///   • Screen OCR via `ScreenCaptureEngine` (user-initiated conversations only)
///
/// `AppDelegate` owns one instance and passes it wherever context is needed.
@MainActor
@Observable
final class PerceptionLayer {

    // MARK: - Sub-sensors

    let clipboardMonitor    = ClipboardMonitor()
    let calendarBridge      = CalendarBridge()
    let screenCaptureEngine = ScreenCaptureEngine()
    private let contextReader = ScreenContextReader()

    // MARK: - Context cache (avoids redundant perception calls within the same poll cycle)

    /// Cached result from the last `captureScreen: false` call.
    private var cachedContext: ScreenContext?
    /// When the cache was last populated.
    private var cachedContextAt: Date?
    /// Cache is considered fresh for 2 seconds — CompanionEngine polls every 30s,
    /// so back-to-back calls within the same cycle always get the cached value.
    private static let contextCacheTTL: TimeInterval = 2.0

    // MARK: - Lifecycle

    func start() async {
        clipboardMonitor.start()
        await calendarBridge.requestAccessIfNeeded()
        contextReader.requestAccessibilityIfNeeded()
        screenCaptureEngine.requestAccessIfNeeded()
    }

    func stop() {
        clipboardMonitor.stop()
    }

    // MARK: - Gather

    /// Assembles a `ScreenContext` snapshot from all sensors.
    ///
    /// - Parameter activity:      Current ActivityMonitor state.
    /// - Parameter captureScreen: When `true`, also captures + OCRs the frontmost
    ///   window via ScreenCaptureKit. This takes ~300–600ms so it should only be
    ///   enabled for user-initiated conversations, NOT for CompanionEngine polls.
    ///
    /// For `captureScreen: false` calls, results are cached for `contextCacheTTL` seconds.
    /// This prevents redundant AppleScript + pasteboard reads when the CompanionEngine
    /// poll cycle triggers multiple back-to-back context requests.
    func gatherContext(activity: ActivityMonitor, captureScreen: Bool = false) async -> ScreenContext {
        // Return cached context if still fresh and no screen OCR is needed
        if !captureScreen,
           let cached = cachedContext,
           let cachedAt = cachedContextAt,
           Date().timeIntervalSince(cachedAt) < Self.contextCacheTTL {
            return cached
        }

        var ctx = ScreenContext()
        ctx.appName    = activity.frontmostAppName
        ctx.appContext = activity.context

        // Browser URL (AppleScript — synchronous, main thread OK here)
        ctx.browserURL = contextReader.browserURL(frontmostBundleID: activity.frontmostBundleID)

        // Selected text
        ctx.selectedText = contextReader.selectedText()

        // Clipboard (latest text change)
        if let clip = clipboardMonitor.latestChange {
            ctx.clipboardText = clip.text
        }

        // Upcoming calendar event
        ctx.upcomingEventSummary = calendarBridge.nextEventSummary(withinMinutes: 20)

        // Screen OCR — only on user-initiated conversations (captureScreen: true)
        if captureScreen {
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? pid_t(0)
            ctx.screenOCRText = await screenCaptureEngine.captureVisibleText(frontmostPID: frontmostPID)
        }

        // Update cache for non-OCR calls
        if !captureScreen {
            cachedContext   = ctx
            cachedContextAt = Date()
        }

        return ctx
    }

    // MARK: - Permissions

    var isAccessibilityGranted: Bool { contextReader.isAccessibilityGranted }
    var isScreenCaptureGranted: Bool { screenCaptureEngine.isAuthorized }
}

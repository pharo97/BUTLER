import Foundation

// MARK: - ScreenContext

/// A snapshot of everything BUTLER can perceive about the user's current state.
/// Passed into PromptBuilder so Claude has full situational awareness.
struct ScreenContext {

    // App
    var appName:    String = ""
    var appContext: ButlerContext = .unknown

    // Browser
    var browserURL: String = ""

    // Selection / clipboard
    var selectedText:  String = ""
    var clipboardText: String = ""

    // Calendar
    var upcomingEventSummary: String = ""   // e.g. "Standup in 8 minutes"

    // Screen OCR (ScreenCaptureKit + Vision) — only populated on user-initiated conversations
    var screenOCRText: String = ""

    // MARK: - Prompt injection

    /// Concise lines injected into the system prompt.
    var promptLines: String {
        var lines: [String] = []

        if !browserURL.isEmpty {
            lines.append("- Browser URL: \(browserURL)")
        }
        if !selectedText.isEmpty {
            let truncated = String(selectedText.prefix(300))
            lines.append("- User has selected: \"\(truncated)\"")
        }
        if !clipboardText.isEmpty {
            let truncated = String(clipboardText.prefix(200))
            lines.append("- Clipboard: \"\(truncated)\"")
        }
        if !upcomingEventSummary.isEmpty {
            lines.append("- Calendar: \(upcomingEventSummary)")
        }
        if !screenOCRText.isEmpty {
            lines.append("- Screen content (OCR): \"\(screenOCRText)\"")
        }

        return lines.joined(separator: "\n")
    }

    var isEmpty: Bool {
        browserURL.isEmpty
        && selectedText.isEmpty
        && clipboardText.isEmpty
        && upcomingEventSummary.isEmpty
        && screenOCRText.isEmpty
    }
}

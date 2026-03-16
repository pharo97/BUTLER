import AppKit
import Foundation

// MARK: - AutomationEngine

/// Parses BUTLER_DO action directives from Claude's responses and executes
/// them as macOS system actions.
///
/// ## How it works
///
/// PromptBuilder instructs Claude to append action lines to responses:
/// ```
///   BUTLER_DO: open_app Safari
///   BUTLER_DO: open_url https://example.com
///   BUTLER_DO: set_volume 40
/// ```
/// These lines are stripped before TTS (the user never hears "BUTLER_DO: …").
/// After speech ends, `executeFromResponse()` scans the full AI response and
/// fires each action.
///
/// Supported actions:
///   • `open_app <Name>`     — launches or focuses an app
///   • `open_url <URL>`      — opens in default browser
///   • `set_volume <0–100>`  — sets system output volume
///   • `run_shortcut <Name>` — triggers a Shortcuts shortcut by name
///
/// New actions can be added by extending the `execute(_ action:)` method.
@MainActor
final class AutomationEngine {

    // MARK: - Parse + execute

    /// Scans `response` for `BUTLER_DO:` lines and runs each action.
    /// Safe to call with any string — silently ignores non-action content.
    func executeFromResponse(_ response: String) async {
        let actions = parse(response)
        for action in actions {
            await execute(action)
        }
    }

    /// Strips `BUTLER_DO:` lines from text (for TTS — the user shouldn't hear these).
    static func stripActions(from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("BUTLER_DO:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Direct API

    /// Opens (or focuses if running) an application by display name.
    func openApp(named name: String) {
        let normalized = name.trimmingCharacters(in: .whitespaces)
        // Try running apps first (focus rather than relaunch)
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == normalized.lowercased()
        }) {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        // Try /Applications
        let candidates: [String] = [
            "/Applications/\(normalized).app",
            "/System/Applications/\(normalized).app",
            "/Applications/Utilities/\(normalized).app"
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return
            }
        }
        // Last resort: let NSWorkspace search by URL scheme / name
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/\(normalized).app"))
    }

    /// Opens a URL in the default browser.
    func openURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        let raw = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Runs a macOS Shortcut by name.
    func runShortcut(named name: String) async {
        let src = "tell application \"Shortcuts\" to run shortcut \"\(name)\""
        await runAppleScript(src)
    }

    /// Sets system output volume (0–100).
    func setVolume(_ level: Int) async {
        let clamped = max(0, min(100, level))
        await runAppleScript("set volume output volume \(clamped)")
    }

    // MARK: - Private

    private struct Action {
        let type:  String
        let param: String
    }

    private func parse(_ response: String) -> [Action] {
        response.split(separator: "\n")
            .compactMap { line -> Action? in
                let s = line.trimmingCharacters(in: .whitespaces)
                guard s.hasPrefix("BUTLER_DO:") else { return nil }
                let body = s.dropFirst("BUTLER_DO:".count).trimmingCharacters(in: .whitespaces)
                let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count >= 1 else { return nil }
                return Action(type: parts[0], param: parts.count > 1 ? parts[1] : "")
            }
    }

    private func execute(_ action: Action) async {
        switch action.type.lowercased() {
        case "open_app":
            openApp(named: action.param)
        case "open_url":
            openURL(action.param)
        case "set_volume":
            if let level = Int(action.param) { await setVolume(level) }
        case "run_shortcut":
            await runShortcut(named: action.param)
        default:
            print("[AutomationEngine] Unknown action: \(action.type)")
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) async -> String {
        // NSAppleScript must run on the main thread on macOS 26+.
        // Dispatching to DispatchQueue.global triggers an internal
        // dispatch_assert_queue(main_q) assertion → _dispatch_assert_queue_fail crash.
        // It can also deadlock: Apple Event replies need the main run loop to
        // pump responses, so calling from a background thread causes a hang +
        // eventual crash (the "just froze" symptom).
        //
        // Since this method is @MainActor, NSAppleScript runs synchronously on
        // the main thread here. Callers already `await` this function so they
        // are suspended while it executes. Automation actions fire only after
        // speech has finished, so the brief main-thread block is imperceptible.
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue ?? ""
    }
}

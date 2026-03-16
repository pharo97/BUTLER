import AppKit
import ApplicationServices

// MARK: - ScreenContextReader

/// Reads ambient context from the screen: browser URL and selected text.
///
/// - Browser URL: AppleScript (reliable across Chrome / Safari / Arc / Brave)
/// - Selected text: Accessibility API (`AXSelectedText`)
///
/// All methods are `@MainActor` because:
///   • `NSAppleScript` must run on main thread
///   • `AXUIElement` queries are synchronous and safe on main thread
@MainActor
final class ScreenContextReader {

    // MARK: - Browser URL

    /// Returns the active tab URL from Chrome, Safari, Arc, or Brave.
    /// Returns empty string if the frontmost app isn't a recognised browser or permission denied.
    func browserURL(frontmostBundleID: String) -> String {
        guard let script = appleScript(for: frontmostBundleID) else { return "" }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return result.stringValue ?? ""
    }

    // MARK: - Selected Text

    /// Returns text currently selected in any app that supports Accessibility.
    func selectedText() -> String {
        guard AXIsProcessTrusted() else { return "" }

        let systemElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let appElement = focusedApp else { return "" }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return "" }

        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
              let text = selectedValue as? String,
              !text.isEmpty else { return "" }

        return text
    }

    // MARK: - Accessibility permission

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    func requestAccessibilityIfNeeded() {
        if !isAccessibilityGranted {
            // Use the raw string key to avoid Swift 6 shared-mutable-state warning
            // on the C-bridged `kAXTrustedCheckOptionPrompt` global.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Private helpers

    private func appleScript(for bundleID: String) -> NSAppleScript? {
        let src: String
        switch bundleID {
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary":
            src = "tell application \"Google Chrome\" to get URL of active tab of front window"
        case "com.apple.Safari":
            src = "tell application \"Safari\" to get URL of current tab of front window"
        case "company.thebrowser.Browser":                    // Arc
            src = "tell application \"Arc\" to get URL of active tab of front window"
        case "com.brave.Browser":
            src = "tell application \"Brave Browser\" to get URL of active tab of front window"
        case "org.mozilla.firefox":
            src = "tell application \"Firefox\" to get URL of current tab of front window"
        default:
            return nil
        }
        return NSAppleScript(source: src)
    }
}

import AppKit
import CoreGraphics

// MARK: - HotkeyManager

/// Registers a global ⌥Space hotkey that triggers BUTLER from any app.
///
/// Requires "Input Monitoring" permission (System Settings > Privacy & Security
/// > Input Monitoring). Without it the monitor installs but events never fire.
///
/// Usage:
///   1. Call `start()` in AppDelegate after the window is up.
///   2. Set `onActivate` to the closure that should fire (e.g. toggle mic).
///   3. If `needsInputMonitoringPermission` is true, call `requestPermission()`
///      which opens System Settings. The user must re-launch the app after granting.
@MainActor
@Observable
final class HotkeyManager {

    // MARK: - State

    /// True while the global monitor is installed and active.
    private(set) var isMonitoring: Bool = false

    /// True when Input Monitoring permission hasn't been granted yet.
    var needsInputMonitoringPermission: Bool = false

    // MARK: - Callback

    /// Called on the main actor when the hotkey fires.
    var onActivate: (() -> Void)?

    // MARK: - Private

    private var globalMonitor: Any?

    // keyCode 49 = Space bar on all Mac keyboards
    private static let hotkeyCode: UInt16 = 49

    // MARK: - Lifecycle

    func start() {
        // Check Input Monitoring permission
        if CGPreflightListenEventAccess() {
            installMonitor()
        } else {
            needsInputMonitoringPermission = true
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        isMonitoring = false
    }

    // MARK: - Permission

    /// Opens System Settings > Privacy > Input Monitoring.
    /// The user must toggle the app on, then re-launch BUTLER.
    func requestPermission() {
        CGRequestListenEventAccess()
    }

    /// Re-checks permission — call after the user returns from System Settings.
    func recheckPermission() {
        if CGPreflightListenEventAccess() {
            needsInputMonitoringPermission = false
            if !isMonitoring { installMonitor() }
        }
    }

    // MARK: - Private

    private func installMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            // ⌥ (option) + Space — no other modifiers
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .option, event.keyCode == Self.hotkeyCode else { return }
            Task { @MainActor in self.onActivate?() }
        }
        isMonitoring = globalMonitor != nil
    }
}

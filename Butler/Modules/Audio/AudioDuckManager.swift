import Foundation

// MARK: - AudioDuckManager

/// Ducks system output volume when BUTLER speaks so its voice is clearly audible
/// over music, then restores volume to its original level when speaking ends.
///
/// This is the "whisper over music" feature from the product brief.
///
/// Implementation: uses `NSAppleScript` to set/get `output volume` (0–100).
/// Non-sandboxed non-App-Store apps can run AppleScript freely.
/// Volume changes are fire-and-forget (async on a background thread so they
/// don't block the audio pipeline).
@MainActor
final class AudioDuckManager {

    // MARK: - Configuration

    /// Volume level during speech (0–100). 30% allows BUTLER to be clearly heard
    /// while still letting the user know music is playing underneath.
    static let duckLevel: Int = 30

    // MARK: - State

    private var savedVolume: Int = 50   // Restored after speech
    private var isDucked:    Bool = false

    // MARK: - Duck / Restore

    /// Lowers system volume before BUTLER starts speaking.
    /// Saves current volume for restoration.
    func duck() {
        guard !isDucked else { return }
        savedVolume = currentVolume()
        // Only duck if user's volume is above the duck level
        guard savedVolume > Self.duckLevel else { return }
        setVolume(Self.duckLevel)
        isDucked = true
    }

    /// Restores system volume to pre-duck level after BUTLER finishes speaking.
    func restore() {
        guard isDucked else { return }
        setVolume(savedVolume)
        isDucked = false
    }

    // MARK: - Private helpers

    private func currentVolume() -> Int {
        let script = NSAppleScript(source: "output volume of (get volume settings)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return Int(result?.int32Value ?? 50)
    }

    private func setVolume(_ level: Int) {
        let clamped = max(0, min(100, level))
        // NSAppleScript requires the main thread on macOS 26+. Running it on
        // DispatchQueue.global triggers dispatch_assert_queue(main_q) inside
        // NSAppleScript and can deadlock (Apple Event replies need the main run
        // loop to be pumping). Task { @MainActor in } defers to the main actor
        // without blocking the current call — the volume change fires as soon as
        // the current @MainActor frame yields, keeping this call non-blocking.
        Task { @MainActor in
            let script = NSAppleScript(source: "set volume output volume \(clamped)")
            script?.executeAndReturnError(nil)
        }
    }
}

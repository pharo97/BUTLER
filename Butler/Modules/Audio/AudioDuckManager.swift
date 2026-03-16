import Foundation
import CoreAudio

// MARK: - AudioDuckManager

/// Ducks system output volume when BUTLER speaks so its voice is clearly audible
/// over music, then restores volume to its original level when speaking ends.
///
/// ## Why CoreAudio instead of NSAppleScript
///
/// The original `NSAppleScript` implementation called `executeAndReturnError()`
/// **synchronously on `@MainActor`**. `NSAppleScript` delivers Apple Events through
/// the main run loop — but the main run loop is blocked waiting for `executeAndReturnError`
/// to return. The Apple Event response can never be delivered → **permanent deadlock**.
/// The app freezes and requires a force-quit.
///
/// `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData` are CoreAudio APIs
/// that execute in-process (no IPC), complete in microseconds, and are thread-safe.
/// They do not interact with the main run loop in any way.
@MainActor
final class AudioDuckManager {

    // MARK: - Configuration

    /// Volume level during speech (0–100). 30% allows BUTLER to be clearly heard
    /// while still letting the user know music is playing underneath.
    static let duckLevel: Int = 30

    // MARK: - State

    private var savedVolume: Float = 0.5   // Restored after speech (0.0–1.0 scalar)
    private var isDucked:    Bool  = false

    // MARK: - Duck / Restore

    /// Lowers system volume before BUTLER starts speaking.
    /// Saves current volume for restoration. Non-blocking — completes in microseconds.
    func duck() {
        guard !isDucked else { return }
        let current = mainOutputVolume()
        savedVolume = current
        let duckFloat = Float(Self.duckLevel) / 100.0
        guard current > duckFloat else { return }
        setMainOutputVolume(duckFloat)
        isDucked = true
    }

    /// Restores system volume to pre-duck level after BUTLER finishes speaking.
    func restore() {
        guard isDucked else { return }
        setMainOutputVolume(savedVolume)
        isDucked = false
    }

    // MARK: - CoreAudio volume

    /// Reads the virtual main output volume of the default output device.
    ///
    /// Uses `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` ('vMVl').
    /// This is the same scalar value shown in macOS System Settings → Sound.
    /// Returns 0.5 (50%) as a safe fallback if the device can't be queried.
    private func mainOutputVolume() -> Float {
        let device = defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return 0.5 }

        var address = AudioObjectPropertyAddress(
            mSelector: kVMVl,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0.5
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : 0.5
    }

    /// Sets the virtual main output volume of the default output device.
    /// `volume` is a scalar in 0.0–1.0.
    private func setMainOutputVolume(_ volume: Float) {
        let device = defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kVMVl,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var vol = Float32(max(0.0, min(1.0, volume)))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &vol)
    }

    /// Returns the `AudioDeviceID` of the system default output device,
    /// or `kAudioObjectUnknown` if it cannot be determined.
    private func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var address  = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size   = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : AudioDeviceID(kAudioObjectUnknown)
    }
}

// MARK: - Constants

/// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` = 'vMVl'
///
/// This AudioHardwareService selector reads/writes the "virtual main volume" —
/// the single scalar knob that maps to the master volume slider in System Settings.
/// Defined as a file-level constant because AudioHardwareService.h is not always
/// bridged directly under Swift 6.2.3 / macOS 26.
private let kVMVl: AudioObjectPropertySelector = 0x764D566C  // 'vMVl'

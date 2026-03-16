import CoreAudio
import Observation

// MARK: - AudioDeviceManager

/// Enumerates available CoreAudio devices and persists the user's
/// preferred microphone selection in UserDefaults.
///
/// ## Design
///
/// Device enumeration uses low-level `AudioObjectGetPropertyData` calls
/// because `AVFoundation` doesn't expose a cross-device picker on macOS
/// (unlike iOS, which has `AVAudioSession.availableInputs`).
///
/// The selected input `AudioDeviceID` is handed to `VoiceSystem.listen()`
/// on each activation so the engine routes through the correct microphone.
///
/// ## Output devices
///
/// `AVSpeechSynthesizer` follows the system default output device automatically.
/// We enumerate output devices for display purposes but routing is read-only
/// until a future update routes TTS through AVAudioEngine.
@MainActor
@Observable
final class AudioDeviceManager {

    // MARK: - Model

    struct AudioDevice: Identifiable, Hashable {
        let id:        AudioDeviceID
        let name:      String
        let uid:       String
        let hasInput:  Bool
        let hasOutput: Bool
    }

    // MARK: - Observable state

    private(set) var inputDevices:  [AudioDevice] = []
    private(set) var outputDevices: [AudioDevice] = []

    private(set) var selectedInputUID:  String = ""
    private(set) var selectedOutputUID: String = ""

    // MARK: - UserDefaults keys

    private enum Keys {
        static let inputUID  = "butler.audio.inputUID"
        static let outputUID = "butler.audio.outputUID"
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        selectedInputUID  = d.string(forKey: Keys.inputUID)  ?? ""
        selectedOutputUID = d.string(forKey: Keys.outputUID) ?? ""
        refresh()
    }

    // MARK: - Derived

    /// CoreAudio `AudioDeviceID` for the currently-selected input device.
    /// Returns `0` when nothing is selected (means "use system default").
    var selectedInputDeviceID: AudioDeviceID {
        inputDevices.first(where: { $0.uid == selectedInputUID })?.id ?? 0
    }

    /// CoreAudio `AudioDeviceID` for the currently-selected output device.
    /// Returns `0` when nothing is selected (means "use system default").
    var selectedOutputDeviceID: AudioDeviceID {
        outputDevices.first(where: { $0.uid == selectedOutputUID })?.id ?? 0
    }

    // MARK: - Selection

    func selectInput(_ device: AudioDevice) {
        selectedInputUID = device.uid
        UserDefaults.standard.set(device.uid, forKey: Keys.inputUID)
    }

    func selectOutput(_ device: AudioDevice) {
        selectedOutputUID = device.uid
        UserDefaults.standard.set(device.uid, forKey: Keys.outputUID)
    }

    // MARK: - Refresh

    /// Re-enumerates all CoreAudio devices. Call when devices change
    /// (e.g. USB mic plugged in) or when the settings panel opens.
    func refresh() {
        let devices = enumerateDevices()
        inputDevices  = devices.filter(\.hasInput)
        outputDevices = devices.filter(\.hasOutput)

        // Validate stored selections still exist; fall back to system default.
        if !inputDevices.isEmpty && !inputDevices.contains(where: { $0.uid == selectedInputUID }) {
            selectedInputUID = inputDevices.first?.uid ?? ""
            UserDefaults.standard.set(selectedInputUID, forKey: Keys.inputUID)
        }
        if !outputDevices.isEmpty && !outputDevices.contains(where: { $0.uid == selectedOutputUID }) {
            selectedOutputUID = outputDevices.first?.uid ?? ""
            UserDefaults.standard.set(selectedOutputUID, forKey: Keys.outputUID)
        }
    }

    // MARK: - CoreAudio enumeration (nonisolated — safe to call from any context)

    private nonisolated func enumerateDevices() -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids   = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap { deviceID in
            guard
                let name = stringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString),
                let uid  = stringProperty(deviceID, kAudioDevicePropertyDeviceUID)
            else { return nil }

            let hasInput  = streamCount(deviceID, scope: kAudioDevicePropertyScopeInput)  > 0
            let hasOutput = streamCount(deviceID, scope: kAudioDevicePropertyScopeOutput) > 0
            guard hasInput || hasOutput else { return nil }

            return AudioDevice(id: deviceID, name: name, uid: uid,
                               hasInput: hasInput, hasOutput: hasOutput)
        }
    }

    /// Reads a CFString property from a CoreAudio device.
    private nonisolated func stringProperty(
        _ id:       AudioDeviceID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        // CoreAudio writes a retained CFStringRef into the buffer.
        // We use Unmanaged<CFString> to correctly bridge ownership.
        var result: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &result) == noErr else { return nil }
        return result?.takeRetainedValue() as String?
    }

    /// Returns the number of audio streams in the given scope (input or output).
    private nonisolated func streamCount(
        _ id:   AudioDeviceID,
        scope:  AudioObjectPropertyScope
    ) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope:    scope,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }

        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount:  Int(size),
            alignment:  MemoryLayout<AudioBufferList>.alignment
        )
        defer { ptr.deallocate() }

        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr) == noErr else { return 0 }
        let list = ptr.load(as: AudioBufferList.self)
        return Int(list.mNumberBuffers)
    }
}

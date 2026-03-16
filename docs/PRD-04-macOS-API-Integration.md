# PRD-04: BUTLER — macOS API Integration Strategy

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering

---

## 1. Overview

BUTLER is deeply integrated with macOS system APIs to achieve ambient awareness and action execution. This document specifies which APIs are used, how, what entitlements are required, and the limitations engineers must account for.

All API usage is gated by permission tier. APIs in Tier 1+ are only initialized after the user has granted the corresponding permission.

---

## 2. Window Management APIs

### 2.1 NSPanel (Glass Chamber Window)

```swift
class ButlerPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 480),
            styleMask: [.nonActivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating           // Floats above normal windows
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.titlebarAppearsTransparent = true
    }
}
```

**Key behaviors:**
- `.nonActivatingPanel` — clicking BUTLER does not steal focus from the user's active app
- `.canJoinAllSpaces` — chamber persists across all macOS Spaces
- `.fullScreenAuxiliary` — appears alongside (not over) fullscreen apps

### 2.2 NSVisualEffectView (Glass Material)
```swift
let effectView = NSVisualEffectView()
effectView.blendingMode = .behindWindow
effectView.material = .hudWindow      // or .underWindowBackground for darker glass
effectView.state = .active
effectView.wantsLayer = true
effectView.layer?.cornerRadius = 18
effectView.layer?.masksToBounds = true
```

### 2.3 Detecting Fullscreen / Presentation Mode
```swift
func isUserInPresentationMode() -> Bool {
    let options = NSApplication.shared.currentSystemPresentationOptions
    return options.contains(.fullScreen) ||
           options.contains(.autoHideMenuBar) ||
           options.contains(.disableMenuBarTransparency)
}
```

---

## 3. Accessibility API

### 3.1 Purpose
- Extract browser URL bar hostname (Tier 1)
- Detect active text field context (Tier 2)
- NOT used for reading screen content or keylogging

### 3.2 Entitlement
```xml
<!-- Entitlements.plist -->
<key>com.apple.security.automation.apple-events</key>
<true/>
```
Additionally: User must grant Accessibility permission in System Settings → Privacy & Security → Accessibility.

### 3.3 Browser Domain Extraction
```swift
func extractBrowserDomain(from app: NSRunningApplication) -> String? {
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)

    var focusedWindow: CFTypeRef?
    AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)

    // Traverse AX tree to find URL bar
    // Safari: AXTextField with identifier "WEB_BROWSER_ADDRESS_BAR_IDENTIFIER"
    // Chrome: AXTextField in toolbar area
    // Firefox: Similar pattern

    guard let urlString = extractURLString(from: focusedWindow as! AXUIElement),
          let components = URLComponents(string: urlString),
          let host = components.host else {
        return nil
    }
    return host  // Only return the hostname, nothing else
}
```

### 3.4 Supported Browsers
- Safari (primary)
- Google Chrome
- Firefox
- Arc
- Brave
- Microsoft Edge

Each browser requires specific AX tree traversal paths — maintain a browser-specific adapter per browser.

### 3.5 Idle Time Detection
```swift
import IOKit

func systemIdleTime() -> TimeInterval {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
          IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
        return 0
    }
    defer { IOObjectRelease(iterator) }

    let entry = IOIteratorNext(iterator)
    defer { IOObjectRelease(entry) }

    var dict: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let properties = dict?.takeRetainedValue() as? [String: Any],
          let idleNanoseconds = (properties[kIOHIDIdleTimeKey] as? NSNumber)?.uint64Value else {
        return 0
    }

    return TimeInterval(idleNanoseconds) / 1_000_000_000
}
```

---

## 4. NSWorkspace APIs

### 4.1 Active App Detection
```swift
// Observe frontmost application changes
NSWorkspace.shared.publisher(for: \.frontmostApplication)
    .compactMap { $0 }
    .sink { app in
        self.activityMonitor.handleAppChange(
            bundleID: app.bundleIdentifier ?? "",
            name: app.localizedName ?? "",
            timestamp: Date()
        )
    }
    .store(in: &cancellables)
```

### 4.2 App Launch / Terminate Events
```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil, queue: .main
) { notification in
    // Track app launches for usage profiling
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didTerminateApplicationNotification,
    object: nil, queue: .main
) { notification in
    // Track session end for duration calculation
}
```

### 4.3 Screen Sleep / Wake
```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.screensDidSleepNotification,
    object: nil, queue: .main
) { _ in
    // Pause all monitoring, flush pending logs
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.screensDidWakeNotification,
    object: nil, queue: .main
) { _ in
    // Resume monitoring, reset idle timer
}
```

### 4.4 Video Call Detection
```swift
// Detect Zoom, Teams, Meet, FaceTime — audio capture active
func isVideoCallActive() -> Bool {
    let videoCallBundleIDs = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.google.Chrome",  // Additional check: domain = meet.google.com
        "com.apple.FaceTime",
        "com.webex.meetingmanager"
    ]

    return NSWorkspace.shared.runningApplications.contains { app in
        guard let bundleID = app.bundleIdentifier,
              videoCallBundleIDs.contains(bundleID) else { return false }
        // Additional check: verify audio capture is actually active
        return app.isActive || isCapturingAudio(pid: app.processIdentifier)
    }
}
```

---

## 5. File System APIs

### 5.1 FSEvents — Downloads Folder Monitoring
```swift
class DownloadsFolderMonitor {
    private var eventStream: FSEventStreamRef?
    private let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

    func start() {
        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
            let monitor = Unmanaged<DownloadsFolderMonitor>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
            monitor.handleFileSystemEvent()
        }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [downloadsURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,  // 2 second latency (batch events)
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        )

        FSEventStreamScheduleWithRunLoop(eventStream!, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(eventStream!)
    }

    private func handleFileSystemEvent() {
        // Debounce: wait 5 seconds after last event before scanning
        scanDebouncer.debounce(interval: 5.0) {
            self.scanDownloadsFolder()
        }
    }

    func scanDownloadsFolder() -> FolderScan {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .nameKey],
            options: .skipsHiddenFiles
        )
        // Returns metadata only — no file contents read
        return FolderScan(fileCount: contents?.count ?? 0, files: contents?.map { FileMetadata($0) } ?? [])
    }
}
```

### 5.2 File Operations (Tier 3)
```swift
class FileOperationService {
    // All operations go through this single point for logging + undo registration
    func moveFile(from source: URL, to destination: URL) throws {
        guard userHasConfirmed(action: .move(source: source, destination: destination)) else {
            throw FileOperationError.notConfirmed
        }

        logOperation(.move(source: source, destination: destination))
        try FileManager.default.moveItem(at: source, to: destination)
        registerUndo(source: source, destination: destination)
    }

    func deleteFile(_ url: URL) throws {
        // NEVER permanently delete — always move to Trash
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        logOperation(.trash(url: url))
        // No undo — user can restore from Trash manually
    }
}
```

---

## 6. EventKit (Calendar API)

### 6.1 Tier 2 — Presence Detection Only
```swift
import EventKit

class CalendarMonitor {
    let eventStore = EKEventStore()

    func requestAccess() async throws {
        try await eventStore.requestFullAccessToEvents()
    }

    // ONLY returns whether an event is happening now — no titles, no descriptions
    func hasActiveEventNow() -> Bool {
        let now = Date()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(60),
            calendars: nil
        )
        return !eventStore.events(matching: predicate).isEmpty
    }
}
```

### 6.2 Tier 3 — Event Suggestion (with confirmation)
```swift
func createEvent(title: String, startDate: Date, endDate: Date) async throws {
    guard userHasConfirmed else { throw CalendarError.notConfirmed }

    let event = EKEvent(eventStore: eventStore)
    event.title = title
    event.startDate = startDate
    event.endDate = endDate
    event.calendar = eventStore.defaultCalendarForNewEvents

    try eventStore.save(event, span: .thisEvent)
    logOperation(.createCalendarEvent(title: title, date: startDate))
}
```

---

## 7. Speech APIs

### 7.1 Speech Recognition (SFSpeechRecognizer)
```swift
import Speech

class SpeechInputService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func startListening() throws {
        // Check authorization
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechError.notAuthorized
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest!) { result, error in
            if let result = result, result.isFinal {
                let transcript = result.bestTranscription.formattedString
                self.handleTranscription(transcript)
            }
        }
    }
}
```

### 7.2 Text-to-Speech (AVSpeechSynthesizer)
```swift
import AVFoundation

class SpeechOutputService {
    private let synthesizer = AVSpeechSynthesizer()
    var onAmplitude: ((Float) -> Void)?  // Fed to pulse renderer

    func speak(_ text: String, voice: VoicePreset) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice.avVoice
        utterance.rate = voice.rate         // 0.4 – 0.6 range
        utterance.pitchMultiplier = voice.pitch
        utterance.postUtteranceDelay = 0.1

        synthesizer.speak(utterance)
    }

    // Override for amplitude extraction (for animation sync)
    // Uses AVAudioEngine tap on synthesizer output bus
}
```

---

## 8. AppleScript Integration (Tier 3)

### 8.1 Execution Model
```swift
class AppleScriptExecutor {
    // Maximum execution time before timeout
    static let timeout: TimeInterval = 10.0

    func execute(script: String) async throws -> String {
        guard isScriptApproved(script) else { throw ExecutionError.notApproved }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)
                if let error { throw ExecutionError.scriptFailed(error.description) }
                return result?.stringValue ?? ""
            }

            group.addTask {
                try await Task.sleep(for: .seconds(Self.timeout))
                throw ExecutionError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // Scripts are shown to user before execution — never run blind
    func isScriptApproved(_ script: String) -> Bool {
        // Checks against user's approved script list
        return approvedScripts.contains(script.hash)
    }
}
```

### 8.2 Allowed AppleScript Operations
- File and folder operations in user-granted paths
- Open/close/activate applications
- Interact with Finder, Mail, Calendar
- Trigger specific Shortcuts

### 8.3 Prohibited AppleScript Operations
- Network operations (`do shell script "curl ..."`)
- System preference modifications
- Account credential access
- Any shell command execution

---

## 9. Shortcuts Integration

```swift
// Trigger via URL scheme — no entitlement required
func triggerShortcut(named name: String) {
    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
    let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")!
    NSWorkspace.shared.open(url)
    logOperation(.triggeredShortcut(name: name))
}
```

---

## 10. macOS Focus / Do Not Disturb Detection

```swift
import UserNotifications

func isDoNotDisturbActive() async -> Bool {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return settings.authorizationStatus == .authorized &&
           // Check current Focus mode via NSWorkspace if available in macOS 15+
           NSWorkspace.shared.currentFocusMode != nil
}
```

---

## 11. Screen Recording / Screen Share Detection

```swift
// Detect if screen is being captured by another app
func isScreenBeingRecorded() -> Bool {
    // CGWindowList approach — check if capture session is active
    if #available(macOS 15.0, *) {
        return SCShareableContent.isScreenRecordingActive
    } else {
        // Fallback: check for known screen recording processes
        let recorderBundleIDs = ["com.apple.screencaptureui", "com.obsproject.obs-studio"]
        return NSWorkspace.shared.runningApplications.contains { app in
            recorderBundleIDs.contains(app.bundleIdentifier ?? "")
        }
    }
}
```

---

## 12. Entitlements Summary

### Direct Distribution Build (Full capability)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Core -->
    <key>com.apple.security.app-sandbox</key><false/>

    <!-- File access -->
    <key>com.apple.security.files.downloads.read-write</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>

    <!-- Automation -->
    <key>com.apple.security.automation.apple-events</key><true/>

    <!-- Audio (microphone) -->
    <key>com.apple.security.device.audio-input</key><true/>

    <!-- Speech recognition -->
    <key>com.apple.security.personal-information.speech-recognition</key><true/>

    <!-- Calendar -->
    <key>com.apple.security.personal-information.calendars</key><true/>
</dict>
</plist>
```

### App Store Build (Sandboxed — reduced capability)
```xml
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.files.downloads.read-only</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.device.audio-input</key><true/>
    <key>com.apple.security.personal-information.speech-recognition</key><true/>
    <key>com.apple.security.personal-information.calendars</key><true/>
    <!-- AppleScript automation EXCLUDED — not available in sandbox -->
    <!-- FSEvents on arbitrary paths EXCLUDED -->
</dict>
```

---

## 13. Known API Limitations & Mitigations

| Limitation | Impact | Mitigation |
|-----------|--------|-----------|
| AX API requires explicit user grant in System Settings | Tier 1 blocked until granted | Clear onboarding prompt, link directly to System Settings pane |
| App Sandbox blocks AppleScript | Tier 3 unavailable in App Store build | Distribute two builds; direct download for full capability |
| SFSpeechRecognizer requires internet for some locales | STT may fail offline | Fallback to local Whisper model; surface offline mode clearly |
| FSEvents does not report file contents | Good — intentional | Feature not needed; metadata only |
| EventKit content unavailable (calendar titles) | Tier 2 can only detect event presence | Sufficient for "you have a meeting" detection use case |
| CGSSessionScreenSharingActive is private API | Screen share detection fragile | Use process name heuristic as fallback; document limitation |
| macOS Gaming Mode (macOS 14+) | May block global hotkeys | Detect via `com.apple.GameMode` notification; warn user |

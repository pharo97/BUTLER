# PRD-18: BUTLER — Anti-Intrusiveness Framework

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering / Product

---

## 1. Principle

The primary failure mode of AI assistants is interruption at the wrong moment. Once a user mutes or uninstalls an assistant, they rarely return. This document defines the complete, non-negotiable ruleset that governs when BUTLER may and may not speak.

Every rule in this document is implemented as code — not as a guideline. Product decisions cannot override hardcoded suppression rules (Section 3). Configuration can only tighten the system, never loosen past the hardcoded floor.

---

## 2. Suppression Hierarchy

Rules are evaluated in strict priority order. A rule higher in the hierarchy overrides all rules below it.

```
Priority 1: HARDCODED KILL SWITCHES (cannot be disabled by any user or product decision)
Priority 2: User-Defined Mute Controls
Priority 3: Scheduled Suppression (Quiet Hours)
Priority 4: Adaptive Suppression (reinforcement-based)
Priority 5: Scoring Threshold (intervention score < 0.65)
Priority 6: Frequency Cap (≤ 3/hour)
Priority 7: Cooldown (per trigger type)
```

---

## 3. Priority 1: Hardcoded Kill Switches

These conditions result in complete suppression of all proactive suggestions and voice output. They cannot be disabled, overridden by configuration, or bypassed by the AI. The only way to change this behavior is to change the source code.

### 3.1 Active Video Call

**Detection method:**
```swift
func isVideoCallActive() -> Bool {
    let videoCallApps: [String: String] = [
        "us.zoom.xos":               "Zoom",
        "com.microsoft.teams":        "Microsoft Teams",
        "com.microsoft.teams2":       "Microsoft Teams (new)",
        "com.google.Chrome":          "Chrome (check domain = meet.google.com)",
        "com.apple.FaceTime":         "FaceTime",
        "com.cisco.webex.meetings":   "Webex",
        "com.skype.skype":            "Skype",
        "com.loom.desktop":           "Loom",
        "com.discord.discord":        "Discord (check: voice channel active)"
    ]

    return NSWorkspace.shared.runningApplications.contains { app in
        guard let bundleID = app.bundleIdentifier,
              videoCallApps[bundleID] != nil else { return false }
        // Additional check: is audio capture active for this PID?
        return app.isActive || isAudioCapturingActive(pid: app.processIdentifier)
    }
}
```

**Behavior during active video call:**
- All proactive suggestions: silenced
- TTS voice output: silenced
- Glass Chamber animation: dims to near-invisible (opacity 0.1)
- Pulse: minimal 1fps heartbeat
- User-initiated voice queries: still accepted (microphone is not blocked)

**Recovery:** Automatic. BUTLER resumes normal behavior within 5 seconds of video call ending.

---

### 3.2 Screen Sharing

**Detection method:**
```swift
func isScreenBeingShared() -> Bool {
    // macOS 15+: use ScreenCaptureKit
    if #available(macOS 15.0, *) {
        return SCShareableContent.currentScreenSharingStatus == .active
    }

    // Fallback: check for known screen sharing processes
    let screenShareBundleIDs = [
        "com.apple.screencaptureui",   // macOS built-in screen sharing
        "com.obsproject.obs-studio",   // OBS Studio
        "com.loom.desktop",            // Loom
        "tv.cleanshot.mac"             // CleanShot X (recording mode)
    ]

    return NSWorkspace.shared.runningApplications.contains {
        screenShareBundleIDs.contains($0.bundleIdentifier ?? "")
    }
}
```

**Behavior:** Identical to active video call.

---

### 3.3 Fullscreen Presentation

**Detection method:**
```swift
func isFullscreenPresentation() -> Bool {
    let presentationOptions = NSApplication.shared.currentSystemPresentationOptions
    let isFullscreen = presentationOptions.contains(.fullScreen)

    if !isFullscreen { return false }

    // Distinguish: productive fullscreen (terminal, IDE) vs presentation
    let presentationApps = [
        "com.apple.iWork.Keynote",
        "com.microsoft.Powerpoint",
        "com.google.Chrome",   // browser fullscreen (often presentations)
        "org.mozilla.firefox"
    ]

    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          let bundleID = frontApp.bundleIdentifier else { return false }

    return presentationApps.contains(bundleID)
}
```

**Note:** Fullscreen terminal (iTerm2, Terminal.app) is NOT treated as a presentation. BUTLER may still suggest in this context (subject to scoring).

**Behavior:** Identical to active video call.

---

### 3.4 macOS Focus Mode (System-level)

**Detection method:**
```swift
// Detect system-level Focus/Do Not Disturb
func isSystemFocusActive() -> Bool {
    let settings = UNUserNotificationCenter.current().notificationSettings
    // macOS Focus mode suppresses notifications — use same signal
    // macOS 14+: query focus mode status if API is available
    if #available(macOS 14.0, *) {
        // Use NFCoreHaptics or system Focus API if available
        // Fallback: check notification authorization and current interruption level
        return UNNotificationInterruptionLevel.timeSensitive.rawValue > 0
        // Accurate implementation requires Focus API entitlement
    }
    return false
}
```

**Note:** This detects the macOS system-level Focus mode (iPhone-style), not BUTLER's internal Focus Mode. Both separately suppress suggestions.

---

### 3.5 Gaming Mode

**Detection method:**
```swift
func isGamingMode() -> Bool {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }

    let isFullscreen = NSApplication.shared.currentSystemPresentationOptions.contains(.fullScreen)
    if !isFullscreen { return false }

    // Check app category
    let category = frontApp.applicationURL.flatMap {
        Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }

    if category == kUTTypeGame as String { return true }

    // Heuristic: fullscreen + sustained high GPU (measured over 30s window)
    return isFullscreen && gpuUsageMonitor.sustained30sAverage > 0.60
}
```

**Behavior:** Identical to active video call.

---

## 4. Priority 2: User-Defined Mute Controls

### 4.1 Global Mute

**Trigger:** User presses the Global Mute keyboard shortcut (default: `⌘⌥M`, configurable)
**Scope:** All proactive suggestions and voice output silenced. User-initiated queries still work.
**Duration:** Until unmuted (same shortcut or Glass Chamber button)
**Persistence:** Session-only — cleared on app restart
**Visual:** Pulse dims 50%, Glass Chamber shows "Muted" indicator

### 4.2 BUTLER Focus Mode

**Trigger:** User activates via Glass Chamber quick control or `butler config set focus_mode true`
**Scope:** All proactive suggestions suppressed. Voice still available for user-initiated queries.
**Duration:** Until deactivated
**Persistence:** Persisted in config.json — survives restart
**Visual:** Pulse shows subtle blue tint, status shows "Focus Mode"

### 4.3 Session Silence

**Trigger:** User dismisses a suggestion and selects "Silence for this session"
**Scope:** No proactive suggestions for remainder of current session
**Duration:** Until app restart
**Persistence:** Session-only

---

## 5. Priority 3: Scheduled Suppression (Quiet Hours)

**Configuration:** `butler config set permissions.quiet_hours.start 22:00` and `.end 08:00`

**Behavior during Quiet Hours:**
- All proactive suggestions silenced
- TTS output for proactive suggestions silenced
- User-initiated queries fully functional
- Glass Chamber visible but pulse at reduced intensity

**Cross-midnight handling:**
```swift
func isInQuietHours() -> Bool {
    let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
    let start = config.quietHours.start  // e.g., hour: 22, minute: 0
    let end   = config.quietHours.end    // e.g., hour: 8,  minute: 0

    let nowMinutes   = now.hour! * 60 + now.minute!
    let startMinutes = start.hour * 60 + start.minute
    let endMinutes   = end.hour * 60 + end.minute

    if startMinutes < endMinutes {
        // Same day: e.g., 09:00–17:00
        return nowMinutes >= startMinutes && nowMinutes < endMinutes
    } else {
        // Crosses midnight: e.g., 22:00–08:00
        return nowMinutes >= startMinutes || nowMinutes < endMinutes
    }
}
```

---

## 6. Priority 4: Adaptive Suppression

### 6.1 Per-Trigger Auto-Suppression

If a user dismisses the same trigger type 3 times within 7 days:
- That trigger type is suppressed for 7 days
- Stored in `suppressed_triggers` table
- Visible in `butler permissions status` and Permission Dashboard
- User can manually clear via `butler reset suppression`

```swift
func checkAutoSuppression(triggerType: TriggerType, profile: BehaviorProfile) -> Bool {
    let recentDismissals = profile.dismissalCount(for: triggerType, within: .days(7))
    if recentDismissals >= 3 {
        learningSystem.suppressTrigger(triggerType, until: Date().addingTimeInterval(7 * 86400),
                                       reason: .auto3xDismiss)
        return true  // suppressed
    }
    return false
}
```

### 6.2 Tolerance Floor

When user tolerance score drops below 20 (out of 100):
- All non-critical proactive suggestions cease
- Only critical alerts (e.g., API key expired) continue
- User is shown a single message: "I've noticed you prefer fewer interruptions. I'll stay quiet unless it's important."
- Tolerance can only recover through positive engagement; it does not auto-reset over time

---

## 7. Priority 5: Intervention Score Threshold

```
Intervention Score = (Context Weight × User Tolerance × Time Modifier × Frequency Decay)
```

**Threshold:** 0.65 (default). Adjustable via Sensitivity Slider in range [0.5, 0.9].

| Slider Position | Effective Threshold | Interpretation |
|----------------|-------------------|----------------|
| Min (0) | 0.5 | More suggestions (less filtering) |
| Default (50) | 0.65 | Balanced |
| Max (100) | 0.9 | Very few suggestions (strict filtering) |

**Time Modifier values:**

| Time Window | Modifier |
|------------|---------|
| 9 AM – 5 PM (work hours) | 1.0 |
| 5 PM – 9 PM (evening) | 0.75 |
| 9 PM – 11 PM (late evening) | 0.5 |
| 11 PM – 6 AM (night) | 0.3 |
| 6 AM – 9 AM (morning) | 0.8 |

**Frequency Decay:**
```swift
func frequencyDecay(for triggerType: TriggerType, lastFired: Date?) -> Double {
    guard let lastFired = lastFired else { return 1.0 }
    let hoursSince = Date().timeIntervalSince(lastFired) / 3600
    let cooldownHours = rule(for: triggerType).cooldownHours  // e.g., 4.0
    return min(1.0, hoursSince / cooldownHours)
}
```

---

## 8. Priority 6: Frequency Cap

Maximum 3 proactive suggestions per rolling 60-minute window.

```swift
actor FrequencyCapTracker {
    private var recentInterventions: [Date] = []

    func canFire() -> Bool {
        let cutoff = Date().addingTimeInterval(-3600)
        recentInterventions.removeAll { $0 < cutoff }
        return recentInterventions.count < 3
    }

    func recordFired() {
        recentInterventions.append(Date())
    }
}
```

This cap applies globally across all trigger types. It is tracked in-memory only (not persisted). Resets on app restart.

---

## 9. Priority 7: Per-Trigger Cooldown

Each trigger type has an individual cooldown window. The same trigger cannot fire again until the cooldown expires.

| Trigger Type | Cooldown |
|-------------|---------|
| `downloads_clutter` | 4 hours |
| `idle_detection` | 2 hours |
| `app_switch_burst` | 30 minutes |
| `late_night` | 24 hours |
| `calendar_gap` | 6 hours |
| `focus_suggestion` | 1 hour |

Cooldown is tracked in `trigger_history` table (persisted).

---

## 10. Voice Output Rules

In addition to suggestion suppression, TTS voice output follows these rules:

1. **Never speak unprompted at volume** — proactive suggestions use reduced volume (70% of configured volume)
2. **Never cut off user input** — if STT detects voice activity, TTS output pauses
3. **Speak once** — if a suggestion is dismissed, it is never re-spoken in the same session
4. **Maximum utterance length (unprompted):** 2 sentences
5. **Silence threshold before speaking:** BUTLER waits 500ms after any keyboard/mouse activity before speaking a proactive suggestion

---

## 11. Interruption Audit Log

Every intervention attempt is logged, including suppressed ones:

```sql
INSERT INTO interactions (
    timestamp, trigger_type, outcome,
    intervention_score, suppression_reason, session_id
) VALUES (
    now(), 'downloads_clutter', 'suppressed_video_call',
    0.72, 'video_call_active', session_id
);
```

This allows `butler history list --type suggestion` to show the user why suggestions were suppressed, building transparency and trust.

---

## 12. Prohibited AI Behaviors

These are constraints placed on the Claude system prompt and enforced by the Intervention Engine. They cannot be changed by personality configuration.

1. Claude must never ask the user to enable higher permission tiers unprompted
2. Claude must never suggest BUTLER is "watching" the user — use "I noticed" not "I'm monitoring"
3. Claude must never guilt-trip or emotionally pressure the user into engagement
4. Claude must never speak during a suppressed context, even if the user message appears to request it
5. Claude must never access or reference specific file contents, email contents, or message text unless the user has explicitly pasted them into the chat
6. Claude must never speculate about the user's emotional state based on activity patterns
7. Claude must never suggest that the user is being unproductive — frame all suggestions as opportunities, not criticisms

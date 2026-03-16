# PRD-03: BUTLER — Security & Permissions Model

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering / Product

---

> **Cross-references:** PRD-11 (CLI commands for permission management) | PRD-12 (IPC authentication) | PRD-14 (code signing + notarization) | PRD-18 (anti-intrusiveness framework) | PRD-19 (security edge cases)

## 1. Security Philosophy

BUTLER's security model is built on one axiom:

> **The difference between genius and spyware is consent and transparency.**

Every permission is:
- Explicitly requested with plain-language explanation
- Individually revocable at any time
- Transparently displayed in the Permission Dashboard at all times
- Time-limited with 90-day re-confirmation prompts
- Never bundled — users grant per-category, not as a package

---

## 2. Permission Tier Architecture

### 2.1 Tier Definitions

#### Tier 0 — Passive Mode (Default)
**What BUTLER can access:** Nothing. BUTLER only responds when directly invoked by the user.
**System APIs used:** None beyond rendering its own UI.
**Entitlements required:** None beyond standard app.
**User experience:** BUTLER is present but silent. Glass Chamber is visible. No proactive suggestions.

---

#### Tier 1 — App-Level Awareness
**What BUTLER can access:**
- Name of the currently active application (frontmost app)
- Browser domain (hostname only, not path, not content)
- Time spent in active app/domain

**What BUTLER cannot access:**
- URL paths or query parameters
- Page content or DOM
- File system
- Other running apps (only frontmost)

**System APIs used:**
- `NSWorkspace.shared.frontmostApplication` (no entitlement required)
- macOS Accessibility API for browser URL bar hostname extraction

**Entitlement required:** `com.apple.security.automation.apple-events` (limited)
**User grant flow:** Single opt-in toggle with explanation dialog
**Displayed in dashboard as:** "App & Browser Awareness"

---

#### Tier 2 — Context Awareness
**What BUTLER can access (each is individually opt-in):**

| Sub-Permission | Access | API |
|---------------|--------|-----|
| Downloads folder | File count, file names, sizes, dates | FSEvents + FileManager |
| Duplicate detection | File name + size hash comparison | FileManager |
| Idle detection | Time since last keyboard/mouse input | IOHIDSystem |
| Calendar presence | Whether a calendar event is active NOW | EventKit (read-only) |
| File metadata | Names, sizes, dates of specified folders | FileManager |

**What BUTLER cannot access:**
- File contents (never opened without per-file confirmation)
- Calendar event titles or descriptions
- Browser page content or DOM
- Any folder not explicitly granted

**Entitlements required:**
- `com.apple.security.files.downloads.read-only`
- `com.apple.security.personal-information.calendars`
- Accessibility permission (for idle detection via IOHIDSystem)

**User grant flow:** Individual toggles per sub-permission, each with plain-language explanation

---

#### Tier 3 — Automation Control
**What BUTLER can do (each action requires per-session or per-action confirmation):**

| Action | Confirmation Required | Reversible |
|--------|----------------------|-----------|
| Move file | Per-action confirmation | Yes (30s undo) |
| Rename file | Per-action confirmation | Yes (30s undo) |
| Create folder | Per-action confirmation | Yes (30s undo) |
| Delete file | Per-action, moves to Trash ONLY | Via Trash |
| Open app | Per-session authorization | N/A |
| Close app | Per-action confirmation | No |
| Draft email | User reviews before sending | N/A |
| Run AppleScript | Per-script, shown to user first | Depends |
| Trigger Shortcut | Per-session authorization per shortcut | Depends |
| Modify calendar | Per-event confirmation | Yes |

**Entitlements required:**
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.automation.apple-events`
- Full Disk Access (user must grant in System Settings)
- Calendar write access

**User grant flow:** Tier 3 is unlocked only after Tier 2 is active for ≥7 days. Requires dedicated onboarding flow with capability demonstration.

---

### 2.2 Permission Dashboard UI

Accessible from: Glass Chamber → Settings → Permissions tab

```
PERMISSIONS DASHBOARD
─────────────────────────────────────────

Tier 0 — Passive Mode
  ● Currently active when: [Focus Mode is on / Quiet Hours]

Tier 1 — App Awareness                              [ENABLED] [Revoke]
  ✓ Detect active application
  ✓ Detect browser domain (amazon.com, not page content)

Tier 2 — Context Awareness
  ✓ Downloads folder monitoring                              [Revoke]
  ✓ Idle time detection                                     [Revoke]
  ✗ Calendar event presence                                 [Enable]
  ✗ File metadata scanning                                  [Enable]

Tier 3 — Automation                                 [LOCKED]
  ↳ Requires Tier 2 active for 7+ days

─────────────────────────────────────────
Site Exclusion List
  amazon.com, youtube.com                                    [Manage]

App Exclusion List
  zoom.us, obs, keynote                                      [Manage]

Quiet Hours: 10:00 PM – 8:00 AM                             [Edit]

Re-confirmation due in: 67 days                              [Review Now]
─────────────────────────────────────────
Last activity log: [View Log]           [Export All Data]  [Delete All Data]
```

---

## 3. Data Security Architecture

### 3.1 Data Classification

| Data Type | Sensitivity | Storage | Transmission |
|-----------|-------------|---------|--------------|
| Conversation history | High | Local, encrypted | Never |
| Behavioral profile | High | Local, encrypted | Summary only (to Claude API) |
| File names/metadata | Medium | Local, encrypted | Never |
| Trigger history | Low | Local, encrypted | Never |
| Personality config | Low | Local, encrypted | Partial (to Claude API in system prompt) |
| API key | Critical | Keychain | Never (sent directly to Anthropic) |

### 3.2 Local Storage Security

- **Database:** SQLite via GRDB.swift + SQLCipher (AES-256-CBC)
- **Key derivation:** PBKDF2 with user's system password hash as seed
- **Keychain:** API key and encryption key stored in `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Database location:** `~/Library/Application Support/Butler/butler.db` (protected directory)
- **Log files:** Rotated every 7 days, encrypted, max 30 days retention

### 3.3 What Is Sent to Claude API

The following — and only the following — is sent in API requests:

```
System Prompt contains:
  - Personality configuration (name, tone, formality level)
  - Behavioral summary (tolerance score, focus state, time of day, active app name)
  - Current intervention template (if proactive suggestion)

Messages contain:
  - User voice/text input (verbatim)
  - Previous conversation turns (recent 10)
  - Compressed summaries of older context

NEVER sent:
  - File contents
  - File paths
  - Calendar event titles or descriptions
  - Browser page content
  - Raw activity logs
  - Any PII beyond what user explicitly types
```

### 3.4 API Key Security
- User enters API key once via secure text field (masked)
- Stored exclusively in macOS Keychain
- Never written to disk in plaintext
- Never included in logs, crash reports, or analytics
- API calls made directly from device to Anthropic (no BUTLER proxy server)

---

## 4. Privacy Threat Model

### 4.1 Threat Actors Considered
1. **Malicious external actors** — network interception, data exfiltration
2. **App Store / platform** — access to stored data
3. **BUTLER company itself** — inadvertent data collection
4. **Physical access** — someone with access to the user's Mac

### 4.2 Mitigations

| Threat | Mitigation |
|--------|-----------|
| Network interception | No behavioral data transmitted; API uses TLS 1.3 |
| Data exfiltration | All data local; no cloud sync; no telemetry |
| Company access | No server infrastructure for user data; zero-knowledge by design |
| Physical access | SQLite encrypted; API key in Keychain (locked on screen lock) |
| Crash reporting | Opt-in only; no sensitive data in crash payloads |

### 4.3 Privacy by Design Principles Applied
- **Data minimization:** Only collect what is necessary for the active tier
- **Purpose limitation:** Data collected for suggestions not used for any other purpose
- **Storage limitation:** Behavioral logs capped at 90 days; auto-purged
- **User control:** Full export and full delete always available
- **Transparency:** All active permissions visible at all times

---

## 5. Activity Logging & Audit Trail

### 5.1 What Is Logged
- Every BUTLER suggestion made (timestamp, type, score)
- Every user response (engaged, dismissed, ignored)
- Every file operation executed (timestamp, action, source, destination)
- Every AppleScript or Shortcut triggered (timestamp, name, outcome)

### 5.2 What Is NOT Logged
- Voice audio (never recorded beyond live transcription)
- File contents
- Screen contents
- Keystrokes
- Browser history

### 5.3 Log Retention
- Activity log: 30 days rolling
- Automation action log: 90 days rolling (for user audit)
- Conversation history: User-controlled (delete per session or all)
- Behavioral profile: User can reset at any time

### 5.4 Log Access
- Available to user via Settings → Privacy → View Log
- Exportable as JSON
- Never transmitted to BUTLER servers

---

## 6. Interruption Suppression — Safety Rules

These rules are hardcoded and cannot be overridden by user settings or AI logic:

```swift
enum SuppressedContext: CaseIterable {
    case activeVideoCall       // Zoom, Teams, Google Meet, FaceTime detected
    case screenSharing         // Any screen share API active
    case fullscreenPresentation // Keynote, PowerPoint, browser fullscreen
    case gameMode              // Fullscreen + sustained high GPU/CPU
    case doNotDisturb          // macOS Focus mode active

    var detectionMethod: String {
        switch self {
        case .activeVideoCall:
            return "NSWorkspace: detect zoom.us, teams.microsoft.com, meet.google.com processes with audio active"
        case .screenSharing:
            return "CGSSessionScreenSharingActive or SCContentSharingSession API"
        case .fullscreenPresentation:
            return "NSApplicationPresentationOptions.fullScreen + app category check"
        case .gameMode:
            return "NSWorkspace app category == .games OR fullscreen + GPU > 60% sustained"
        case .doNotDisturb:
            return "UNUserNotificationCenter current settings"
        }
    }
}
```

---

## 7. Compliance Considerations

### 7.1 macOS App Store
- **Privacy Nutrition Label:** Must declare all data access accurately
- **Entitlements:** Only request what is used; Tier 3 unavailable in sandboxed App Store build
- **Human Interface Guidelines:** Permission requests must follow Apple's permission dialog patterns

### 7.2 GDPR / CCPA
- **GDPR Article 17 (Right to Erasure):** "Delete All Data" function fully satisfies this
- **GDPR Article 15 (Right of Access):** "Export All Data" as JSON satisfies this
- **No EU data transfer:** All data stays on device (no server)
- **CCPA:** No "sale" of personal data; no data transmitted to BUTLER servers

### 7.3 Accessibility API Usage
- Must not be used for surveillance beyond declared purposes
- Disclosure required in App Store privacy nutrition label
- Limited to hostname extraction for browser domain; no DOM reading

---

## 8. Incident Response

### 8.1 Data Breach
- No server-side data = no server breach possible
- Client-side breach: User's Mac is compromised = OS-level issue, not BUTLER-specific
- BUTLER does not have a breach surface for user behavioral data

### 8.2 API Key Compromise
- User notified on next launch if API key fails authentication
- Prompt to replace key via Keychain update
- No BUTLER system has access to user API keys

### 8.3 Bug Disclosure
- Security vulnerabilities reported to: security@[butlerapp.com]
- 90-day responsible disclosure policy
- Priority patch for any issue involving unauthorized data access

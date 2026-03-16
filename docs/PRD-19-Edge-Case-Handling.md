# PRD-19: BUTLER — Edge Case Handling

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering / QA

---

## 1. Overview

This document catalogs known edge cases, their expected behavior, and the implementation requirement for each. Every edge case has a defined outcome — undefined behavior is not acceptable.

Edge cases are grouped by system domain. Each entry includes:
- **Condition:** What triggers this case
- **Expected behavior:** What BUTLER must do
- **Implementation requirement:** How it must be enforced in code
- **Testability:** How this case is verified in testing

---

## 2. Installation & First Launch

### EC-001: App launched before `butler install` is run
**Condition:** User drags .app to Applications and opens it without running the installer.
**Expected behavior:** App launches in reduced mode. Prompts for `butler install` on first interaction with CLI-dependent features. Core voice and chat work.
**Implementation:** Check for `~/.butler/` directory existence on launch. If absent, show one-time "Complete setup" banner in Glass Chamber.
**Testability:** Delete `~/.butler/` before launch. Verify prompt appears.

### EC-002: `/usr/local/bin` is not writable
**Condition:** User does not have admin rights. Terminal installer cannot create CLI symlink.
**Expected behavior:** Installation completes without CLI symlink. User is told explicitly that CLI is unavailable and given the manual command to install it later.
**Implementation:** Catch `EACCES` on symlink creation. Print exact sudo command for manual installation.
**Testability:** Run installer as non-admin user. Verify clear message and no crash.

### EC-003: BUTLER.app not in /Applications
**Condition:** User runs app from Downloads or Desktop without moving to /Applications.
**Expected behavior:** App works. CLI symlink will point to a path that disappears if user moves or deletes the app. On first CLI invocation, check that symlink target is valid. If invalid, prompt re-installation.
**Implementation:** `butler-cli` validates symlink target at startup. Invalid target → print warning and exit 1 with re-install instructions.
**Testability:** Move .app to Desktop, run from there, then invoke `butler status`.

### EC-004: Reinstall over existing installation
**Condition:** User runs `butler install` when BUTLER is already installed.
**Expected behavior:** Exit code 3. Print: "Butler is already installed. Run `butler update` to update." Do not overwrite existing config or data.
**Implementation:** Check for `~/.butler/config.json` existence as install marker.
**Testability:** Run `butler install` twice. Verify exit code 3 and no data loss.

### EC-005: Notarization fails at Gatekeeper
**Condition:** User downloads a DMG from a cached/corrupted URL that has a bad signature.
**Expected behavior:** macOS shows Gatekeeper dialog. BUTLER does not launch. User must redownload.
**Implementation:** This is an OS-level behavior. BUTLER cannot modify Gatekeeper. Publish SHA-256 checksums on download page so users can verify before mounting.
**Testability:** Sign a DMG with an invalid cert intentionally. Verify Gatekeeper blocks it.

---

## 3. API Key & Claude Integration

### EC-006: API key not set
**Condition:** User launches BUTLER without entering an API key.
**Expected behavior:** All Claude-dependent features are disabled. Glass Chamber shows persistent "API key required" message. Voice input is accepted but responds: "I need an API key to think. Please add one in Settings."
**Implementation:** `ClaudeIntegrationLayer` checks Keychain for key on initialization. If absent, publishes `.apiKeyMissing` state. All modules that require Claude subscribe and enter degraded mode.
**Testability:** Delete Keychain item before launch. Verify behavior.

### EC-007: API key is invalid (401 from Claude)
**Condition:** User enters a revoked or incorrect API key.
**Expected behavior:** First 401 response surfaces a Glass Chamber notification: "API key rejected by Anthropic. Please update it in Settings." No retry. Feature degrades to rule-based mode only.
**Implementation:** On `HTTP 401`, do not retry. Set `apiKeyState = .invalid`. Notify Visualization Engine.
**Testability:** Set key to `"sk-invalid"`. Make a voice query. Verify notification and no retry loops.

### EC-008: Claude API rate limited (429)
**Condition:** User makes too many requests in a short period.
**Expected behavior:** Backoff and retry up to 3 times. If all fail, display: "I'm temporarily rate limited. Please wait a moment." Do not queue requests indefinitely.
**Implementation:** Exponential backoff: 1s, 2s, 4s. After 3 failures, surface error to user. Discard the request.
**Testability:** Mock 429 responses in test mode. Verify backoff timing and user message.

### EC-009: Claude API returns empty or malformed response
**Condition:** API returns HTTP 200 but response body is empty or invalid JSON.
**Expected behavior:** Log error. Show: "I received an unexpected response. Please try again." Do not crash.
**Implementation:** Wrap JSON decoding in do-catch. Surface error state on parse failure.
**Testability:** Mock a malformed JSON response in test mode.

### EC-010: Context window exceeded
**Condition:** Conversation history exceeds Claude's context limit.
**Expected behavior:** Background compression runs automatically. User sees no interruption. If compression fails, oldest turns are dropped silently.
**Implementation:** Track estimated token count. Trigger compression at 70% of model's context limit. On compression failure, drop oldest turns.
**Testability:** Create 30+ conversation turns rapidly. Verify background compression fires.

---

## 4. Voice System

### EC-011: Microphone permission denied
**Condition:** User denied microphone access in System Settings.
**Expected behavior:** Voice input is disabled. Glass Chamber shows: "Microphone access needed for voice. Enable in System Settings." Buttons: [Open Settings] [Use Chat Only]. Chat interface remains fully functional.
**Implementation:** `SFSpeechRecognizer.requestAuthorization` and `AVCaptureDevice.requestAccess` are called at setup. On denial, set `voiceState = .microphoneUnavailable`.
**Testability:** Deny microphone in System Settings before first launch. Verify message and no crash.

### EC-012: Microphone access revoked mid-session
**Condition:** User revokes microphone access in System Settings while BUTLER is running.
**Expected behavior:** AVAudioEngine throws on next STT attempt. Catch error. Surface message: "Microphone access was removed. Re-enable in System Settings." Do not crash.
**Implementation:** Wrap all AVAudioEngine start/tap calls in try-catch. Subscribe to `AVCaptureDevice.wasDisconnectedNotification` equivalents.
**Testability:** Revoke microphone in System Settings while BUTLER is recording. Verify graceful recovery.

### EC-013: STT returns low-confidence transcript
**Condition:** SFSpeechRecognizer returns a transcript with `confidence < 0.60`.
**Expected behavior:** BUTLER echoes back what it heard: "I heard: 'organize my fils' — did I get that right?" User can confirm or re-speak.
**Implementation:** Check `SFTranscriptionSegment.confidence` on final result. Below 0.60 → disambiguation flow.
**Testability:** Speak in heavy background noise. Verify disambiguation behavior.

### EC-014: TTS output interrupted by push-to-talk
**Condition:** User presses the push-to-talk hotkey while BUTLER is speaking.
**Expected behavior:** TTS stops immediately. STT activates. BUTLER does not resume previous TTS after STT finishes.
**Implementation:** `AVSpeechSynthesizer.stopSpeaking(at: .immediate)` on hotkey press.
**Testability:** Hold hotkey while BUTLER is mid-sentence. Verify immediate stop.

### EC-015: Wake word false positive during video call
**Condition:** Wake word detection fires while a video call is active (e.g., someone says "hey butler" in a meeting).
**Expected behavior:** BUTLER does not respond. Video call suppression takes priority over wake word.
**Implementation:** `isVideoCallActive()` is checked before any STT session starts. Wake word detection triggers → check suppression → return if suppressed.
**Testability:** Simulate video call active + fire wake word programmatically. Verify no STT activation.

### EC-016: ElevenLabs API unavailable (premium TTS)
**Condition:** ElevenLabs service is down or API key is invalid.
**Expected behavior:** Fallback to native AVSpeechSynthesizer automatically. User sees a one-time notification: "Premium voice unavailable — using native voice."
**Implementation:** `ElevenLabsClient.speak()` failure → fallback to `AVSpeechSynthesizer`. Log warning.
**Testability:** Set ElevenLabs key to invalid value. Verify fallback and notification.

---

## 5. Proactive Suggestions & Intervention

### EC-017: Video call starts while suggestion is mid-delivery
**Condition:** BUTLER begins speaking a suggestion (TTS active) and a Zoom call starts simultaneously.
**Expected behavior:** TTS stops immediately. Suggestion bubble dismissed. No further suggestions for duration of call.
**Implementation:** `isVideoCallActive()` is polled every 2 seconds. On detection: call `voiceSystem.stopSpeaking()` and `visualizationEngine.dismissCurrentSuggestion()`.
**Testability:** Start Zoom while BUTLER is speaking a suggestion. Verify immediate stop and dismissal.

### EC-018: User starts screen sharing while BUTLER animation is visible
**Condition:** User begins screen sharing with Glass Chamber visible.
**Expected behavior:** Glass Chamber animation dims to near-invisible (opacity 0.15). No suggestions fire. User can manually keep it visible if they choose.
**Implementation:** Screen share detection → set chamber opacity to 0.15 and suppress all interventions.
**Testability:** Start screen sharing via macOS menu bar. Verify chamber dims.

### EC-019: Suggestion delivery fails (Glass Chamber minimized/hidden)
**Condition:** Glass Chamber is minimized to orb or hidden when a suggestion fires.
**Expected behavior:** Orb pulses with the suggestion state color. Suggestion waits until user expands the chamber or clicks the orb.
**Implementation:** If chamber is not visible: pulse orb, queue suggestion, deliver when chamber expands.
**Testability:** Collapse chamber to orb. Trigger a suggestion. Verify orb pulses and suggestion appears on expand.

### EC-020: Multiple context triggers fire simultaneously
**Condition:** Downloads clutter AND idle detection AND app switch burst all score above threshold in the same evaluation cycle.
**Expected behavior:** Only the highest-scoring trigger fires. Others are queued and evaluated independently after their cooldown.
**Implementation:** `InterventionEngine` takes only the highest-score candidate per evaluation cycle. Others are discarded (not queued — re-evaluated fresh on next cycle).
**Testability:** Simulate all three triggers simultaneously with mock data. Verify only one fires.

### EC-021: Trigger fires but suggested action is already completed
**Condition:** BUTLER suggests "Your Downloads has 160 files" but user has already sorted them manually since the trigger was queued.
**Expected behavior:** BUTLER should re-check the signal at delivery time. If condition no longer holds (file count now <30), cancel the suggestion silently.
**Implementation:** At delivery time (not at candidate generation time), re-validate the trigger condition before speaking.
**Testability:** Queue trigger. Manually clean Downloads. Wait for delivery. Verify suggestion is cancelled.

---

## 6. Database & Storage

### EC-022: Database corruption detected
**Condition:** `PRAGMA integrity_check` returns errors on startup.
**Expected behavior:** BUTLER creates a backup of the corrupted file (renamed with `.corrupt` suffix), creates a fresh database, and surfaces a notification: "I had to reset my memory due to a database error. Your config is intact."
**Implementation:** Run integrity check before any reads. On failure: rename file, create fresh DB, notify user.
**Testability:** Corrupt `butler.db` manually (write random bytes). Verify recovery flow.

### EC-023: Database locked (concurrent write)
**Condition:** Two writes arrive simultaneously (e.g., CLI command + automated behavioral write).
**Expected behavior:** WAL mode handles this gracefully. No data loss. No deadlock. WAL mode allows concurrent reads during write.
**Implementation:** GRDB.swift with WAL mode enabled handles this. Verify WAL is active in schema setup.
**Testability:** Send concurrent writes via integration test. Verify no lock errors.

### EC-024: Disk full
**Condition:** System disk is full. SQLite cannot write.
**Expected behavior:** Write fails gracefully. Log error. Surface to user: "I can't save to disk — your Mac's storage is full." Continue operating with in-memory state only (no crash).
**Implementation:** Catch SQLite error code `SQLITE_FULL`. Degrade to in-memory mode. Notify user.
**Testability:** Use a small file system image, fill it, then trigger a write. Verify graceful handling.

### EC-025: `~/.butler/` directory deleted while app is running
**Condition:** User manually deletes `~/.butler/` while BUTLER is running.
**Expected behavior:** Next write attempt fails. BUTLER recreates the directory structure and informs the user that settings and history were lost.
**Implementation:** Watch `~/.butler/` with FSEvents. On removal event: recreate directories, reset to defaults, notify user.
**Testability:** Delete `~/.butler/` while app is running. Verify recreation and notification.

### EC-026: API key deleted from Keychain while app is running
**Condition:** User deletes the Keychain item (via Keychain Access.app) while BUTLER is running.
**Expected behavior:** Next Claude API call fails with `SecItemCopyMatching` returning `errSecItemNotFound`. BUTLER notices on next request. Surfaces: "API key is missing. Please re-enter it in Settings."
**Implementation:** On `Keychain.read()` returning nil during an active session: surface error, enter degraded mode.
**Testability:** Delete Keychain item during active session. Make a voice query. Verify error handling.

---

## 7. System & OS Events

### EC-027: macOS major version update (e.g., 15→16)
**Condition:** User updates macOS and Accessibility API or other APIs change behavior.
**Expected behavior:** BUTLER degrades gracefully if an API call fails. Does not crash. Browser domain detection may fail — silently disables that feature and logs a warning.
**Implementation:** All AX API calls wrapped in try-catch with graceful degradation. `butler diagnostics` reports which features are degraded.
**Testability:** Mock AX API failure. Verify feature degradation without crash.

### EC-028: Mac sleeps mid-interaction
**Condition:** Mac goes to sleep while BUTLER is speaking a TTS response or processing an STT input.
**Expected behavior:** AVAudioEngine is suspended automatically by the OS. On wake: STT session is reset, TTS does not resume mid-sentence. BUTLER returns to idle state.
**Implementation:** Subscribe to `NSWorkspace.screensDidSleepNotification`. On sleep: stop any active STT/TTS, reset to idle. On wake: resume monitoring.
**Testability:** Close MacBook lid while BUTLER speaks. Open lid. Verify idle state recovery.

### EC-029: External display disconnected with Glass Chamber on that display
**Condition:** User disconnects a monitor that the Glass Chamber is positioned on.
**Expected behavior:** Window is moved to the main display automatically (macOS default behavior for disconnected display). Glass Chamber is repositioned to a valid location.
**Implementation:** Observe `NSApplication.didChangeScreenParametersNotification`. On fire: check if window is on a valid screen. If not: move to main display's top-right corner.
**Testability:** Position chamber on external display. Disconnect display (simulate via System Settings). Verify window repositions.

### EC-030: Permission revoked for Accessibility API mid-session
**Condition:** User disables Accessibility in System Settings while BUTLER is running.
**Expected behavior:** AX API calls fail. Browser domain extraction silently fails. Tier 1 degrades to app-name-only. No crash.
**Implementation:** Catch all `AXError` returns. On critical error (`AXError.apiDisabled`): disable AX-dependent features, log warning, continue with degraded Tier 1.
**Testability:** Revoke Accessibility in System Settings during an active session. Verify graceful degradation.

### EC-031: Concurrent BUTLER instances
**Condition:** User attempts to launch BUTLER.app a second time.
**Expected behavior:** Second launch detects the running instance (socket already in use), brings the existing instance's Glass Chamber to front, and exits immediately.
**Implementation:** On launch: attempt to bind socket. If `EADDRINUSE`: send a `focus` command to the running instance, then exit.
**Testability:** Launch BUTLER. Launch again from Finder. Verify single instance behavior.

---

## 8. Automation Execution (Tier 3)

### EC-032: File operation target no longer exists
**Condition:** User approves a file move. Between approval and execution, the source file is deleted.
**Expected behavior:** `FileManager.moveItem()` throws `CocoaError.fileNoSuchFile`. Log the error. Notify user: "I couldn't move [filename] — it may have already been moved or deleted."
**Implementation:** Catch all `FileManager` errors. Per-file failure is non-fatal — skip the file and report.
**Testability:** Queue a file move. Delete the source file. Confirm. Verify graceful per-file error.

### EC-033: File operation destination has a naming conflict
**Condition:** User approves moving a file to a destination that already contains a file with the same name.
**Expected behavior:** Before executing, BUTLER checks for conflicts. If found: offers to rename (e.g., `report-2.pdf`). Does not silently overwrite.
**Implementation:** Check for destination conflict before executing any file operation. If conflict: pause and ask user.
**Testability:** Create a file at the destination before the move operation. Verify conflict detection.

### EC-034: AppleScript execution times out
**Condition:** An approved AppleScript hangs for >10 seconds.
**Expected behavior:** BUTLER kills the script process via `Process.terminate()`. Notifies user: "That script timed out. It has been stopped."
**Implementation:** Wrap script execution in `withThrowingTaskGroup`. Cancel after 10 seconds.
**Testability:** Approve an infinite-loop AppleScript. Verify timeout at 10 seconds.

### EC-035: Undo window expires during undo attempt
**Condition:** User clicks "Undo" at exactly 30 seconds (race condition with undo window expiration).
**Expected behavior:** Undo is attempted. If undo action has already been deallocated, user sees: "Undo window has passed. You can manually restore the files from their new location."
**Implementation:** Undo handler is a weak reference. If nil on click: show expired message.
**Testability:** Wait 30 seconds exactly after a file operation. Click Undo at the moment of expiry.

---

## 9. CLI-Specific Edge Cases

### EC-036: BUTLER.app not running when CLI is invoked
**Condition:** `butler status` is called when BUTLER.app is not running.
**Expected behavior:** By default: launch BUTLER.app in headless mode, wait up to 5 seconds for socket to appear, then execute command. With `--no-launch`: exit immediately with code 2.
**Implementation:** In `butler-cli`, check for socket existence. If absent: launch app, poll for socket every 100ms, timeout at 5s.
**Testability:** Kill BUTLER.app. Run `butler status`. Verify auto-launch and successful response.

### EC-037: Socket file is stale (app crashed)
**Condition:** `~/.butler/run/butler.sock` exists (from a previous crashed session) but no process is listening.
**Expected behavior:** `connect()` returns `ECONNREFUSED`. CLI detects stale socket, deletes it, launches app fresh, retries.
**Implementation:** On `ECONNREFUSED` to existing socket: `unlink(socketPath)`, launch app, retry connection.
**Testability:** Create a fake socket file. Run `butler status`. Verify stale detection and recovery.

### EC-038: CLI command requires higher permission tier
**Condition:** `butler speak "move my files"` is run but the user has only Tier 1 active (no automation).
**Expected behavior:** Claude processes the command but does not attempt execution. Response explains the limitation: "I can help you organize files, but you'll need to enable Automation (Tier 3) in Settings or via `butler permissions grant automation` first."
**Implementation:** Claude system prompt includes current tier. Claude is instructed to inform users when capabilities are tier-locked.
**Testability:** Set tier to 1. Run `butler speak "move my downloads"`. Verify informative response.

### EC-039: CLI timeout waiting for streaming response
**Condition:** `butler speak` command is waiting for a Claude streaming response that takes >30 seconds (unlikely but possible under heavy load).
**Expected behavior:** CLI prints partial tokens received so far. After 30 seconds of silence: prints "Request timed out. Partial response above." Exits with code 9.
**Implementation:** `butler-cli` implements a 30-second inactivity timer on the stream. Fires on no new chunks for 30 seconds.
**Testability:** Mock a streaming response that halts mid-stream. Verify 30-second timeout.

### EC-040: Homebrew updates CLI but app is older version
**Condition:** User runs `brew upgrade butler` (CLI only), updating the CLI binary to v1.1.0, but BUTLER.app is still v1.0.0.
**Expected behavior:** CLI reports version mismatch on connection. Suggests updating the app. Core commands (status, config, logs) still function. Commands requiring new features fail gracefully.
**Implementation:** CLI sends its version in every request envelope. App checks for minimum CLI version and vice versa. On mismatch: log warning. On incompatible version: return error with upgrade instructions.
**Testability:** Simulate version mismatch in integration test. Verify warning and graceful degradation.

---

## 10. Edge Case Test Matrix (QA Checklist)

| ID | Description | Automated | Priority |
|----|-------------|-----------|---------|
| EC-001 | App launched before install | Manual | Medium |
| EC-002 | Non-writable /usr/local/bin | CI | High |
| EC-006 | No API key | CI | Critical |
| EC-007 | Invalid API key | CI | Critical |
| EC-008 | API rate limited | CI (mock) | High |
| EC-011 | Microphone denied | Manual | Critical |
| EC-014 | TTS interrupted by push-to-talk | CI | High |
| EC-017 | Video call starts mid-suggestion | CI | Critical |
| EC-021 | Trigger condition resolved before delivery | CI | High |
| EC-022 | Database corruption | CI | Critical |
| EC-024 | Disk full | CI | High |
| EC-027 | macOS update breaks AX API | Manual | High |
| EC-028 | Sleep mid-interaction | Manual | High |
| EC-029 | External display disconnected | Manual | Medium |
| EC-031 | Concurrent BUTLER instances | CI | High |
| EC-034 | AppleScript timeout | CI | High |
| EC-036 | CLI invoked when app not running | CI | High |
| EC-037 | Stale socket file | CI | High |
| EC-040 | Version mismatch (CLI vs app) | CI | Medium |

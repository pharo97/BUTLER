# PRD-16: BUTLER — Data Flow Diagrams

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering

All flows described as text diagrams. Arrows (`→`) indicate data movement. Brackets (`[ ]`) indicate modules. Parentheses indicate data types or conditions.

---

## 1. Voice Interaction Pipeline (User-Initiated)

```
USER presses hotkey (⌘ Space)
         │
         ▼
[AppDelegate] global hotkey handler
         │ startListening()
         ▼
[Voice System — STT]
  AVAudioEngine activates microphone
         │
         │ (PCM audio buffers, 60fps)
         ▼
  SFSpeechAudioBufferRecognitionRequest
         │
         │ (partial transcription strings)
         ▼
  partialResultPublisher → [Visualization Engine]
                              setState(.listening)
         │
USER releases hotkey
         │
         ▼
  SFSpeechRecognizer finalizes transcript
         │
         │ (String: final transcript)
         ▼
[Voice System — STT] publishes finalTranscription
         │
         ▼
[Claude Integration Layer]
  buildSystemPrompt(personality, behaviorProfile ← [Learning System])
  append user message to conversation history
         │
         │ HTTPS POST to api.anthropic.com (streaming)
         ▼
  Claude API → streaming response tokens
         │
         │ (AsyncThrowingStream<String, Error>)
         ▼
[Claude Integration Layer] publishes token stream
         │
  ┌──────┴────────────────────────────────────┐
  │                                           │
  ▼                                           ▼
[Visualization Engine]              [Voice System — TTS]
  setState(.thinking) on start         receives token stream
  setState(.speaking) on first token   buffers tokens into utterances
                                       AVSpeechSynthesizer speaks
                                              │
                                              │ (PCM amplitude, 60fps)
                                              ▼
                                    amplitudePublisher
                                              │
                                              ▼
                                    [Visualization Engine]
                                      setAmplitude(float)
                                      (waveform modulation)
         │
         ▼
[Claude Integration Layer] response complete
  saves assistant turn to conversation history → [Learning System]
         │
         ▼
[Visualization Engine]
  setState(.idle)
```

---

## 2. Proactive Intervention Pipeline

```
[Activity Monitor]
  NSWorkspace observer fires (frontmost app changed)
         │
         │ (ActivitySignal.activeAppChanged)
         ▼
[Activity Monitor] publishes to activityPublisher
         │
         ▼
[Context Analyzer] receives ActivitySignal
  evaluates against rule set (rules.json)
  checks: [Learning System].isSuppressed(triggerType)
         │
         │ condition met?
         │
      NO → discard
         │
      YES
         │
         │ (InterventionCandidate)
         ▼
[Intervention Engine] receives candidate
         │
  1. checks [Permission & Security Manager].isSuppressed()
         │ → suppressed? discard
  2. calls [Reinforcement Scorer].score(candidate, profile)
         │ → score < 0.65? discard
  3. checks cooldown for trigger type (in-memory)
         │ → within cooldown? discard
  4. checks frequency cap (≤3/hour, in-memory)
         │ → cap reached? discard
         │
         │ APPROVED
         │
  ┌──────┴─────────────────────────────────────┐
  │                                            │
  ▼                                            ▼
[Visualization Engine]               [Voice System — TTS]
  setState(.active)                    speaks suggestion text
  expand Glass Chamber 10%
  show suggestion bubble UI
         │
         │
USER RESPONSE
  ┌──────────────┬──────────────┬─────────────────────┐
  │              │              │                     │
  ▼              ▼              ▼                     ▼
ENGAGED      DISMISSED      IGNORED             NEVER ASK
  │              │           (30s)                    │
  │              │              │                     │
  └──────────────┴──────────────┴─────────────────────┘
         │
         ▼ InteractionOutcome
[Reinforcement Scorer]
  updateToleranceScore(outcome)
         │
         ▼
[Learning System]
  persist updated BehaviorProfile
  log interaction to interactions table
         │
         ▼ (if DISMISSED 3x same trigger type)
  write SuppressedTrigger to suppressed_triggers table
```

---

## 3. CLI → IPC → Module Pipeline

```
USER terminal:
$ butler config set personality.name "Sage"
         │
         ▼
[butler-cli binary]
  reads auth token from ~/.butler/run/.auth
  creates Unix socket connection to ~/.butler/run/butler.sock
  sends:
  {"id": "uuid", "command": "config.set", "args": {...}, "auth_token": "..."}
         │
         │ (Unix domain socket, newline-delimited JSON)
         ▼
[CLI Controller Module — BUTLER.app]
  accepts connection
  reads request
  validates auth_token (constant-time compare)
         │
         │ authenticated?
         │
      NO → sends error response, closes connection
         │
      YES
         │
         ▼
  routes to ConfigCommandHandler
         │
         ▼
[Config Store] (in-memory, backed by config.json)
  validates key "personality.name"
  validates value "Sage"
  writes to config.json
  notifies [Claude Integration Layer] → rebuilds system prompt on next request
         │
         ▼
[CLI Controller Module]
  sends response:
  {"id": "uuid", "ok": true, "command": "config.set", "data": {...}}
         │
         │ (Unix domain socket)
         ▼
[butler-cli binary]
  reads response
  formats for display
  prints to stdout:
  "personality.name set to 'Sage'."
  exits with code 0
```

---

## 4. `butler speak` Streaming Pipeline

```
USER:
$ butler speak "What time is my next meeting?"
         │
         ▼
[butler-cli binary]
  connects to socket
  sends: {"command": "speak", "args": {"text": "What time is my next meeting?"}}
         │
         ▼
[CLI Controller → SpeakCommandHandler]
         │
         ▼
[Claude Integration Layer]
  buildSystemPrompt(personality, profile ← [Learning System])
  POST to Claude API (streaming=true)
         │
         │ streaming response tokens arrive
         ▼
[CLI Controller]
  for each token:
    sends: {"type": "stream_chunk", "data": {"text": "You have a"}}
    sends: {"type": "stream_chunk", "data": {"text": " meeting at 3 PM."}}
    sends: {"type": "stream_end", "data": {"exit_code": 0}}
         │
         │ (socket, newline-delimited JSON)
         ▼
[butler-cli binary]
  prints each chunk to stdout as it arrives:
  Alfred: You have a meeting at 3 PM.
  exits 0

SIMULTANEOUSLY:
  [Voice System — TTS] speaks the response
  [Visualization Engine] animates pulse (.thinking → .speaking → .idle)
```

---

## 5. Permission Grant Pipeline

```
USER (CLI):
$ butler permissions grant calendar
         │
         ▼
[CLI Controller → PermissionsCommandHandler]
         │
         ▼
[Permission & Security Manager]
  checks: is calendar permission already granted?
         │ YES → return "already granted"
         │ NO
         ▼
  opens System Settings:
  NSWorkspace.open(URL("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"))
         │ (async — waits for user action)
         ▼
  poll EKEventStore.authorizationStatus() every 2 seconds (max 30 seconds)
         │
         │ status changed to .authorized?
         │
      NO (timeout) → return timeout error
         │
      YES
         ▼
  updates internal permission state
  publishes permissionTierPublisher → subscribers update
         │
         ▼
[Activity Monitor]
  if new tier allows calendar monitoring:
    initializes CalendarMonitor
    begins polling hasActiveEventNow()
         │
         ▼
[CLI Controller]
  sends response: {"ok": true, "data": {"permission": "calendar", "status": "granted"}}
         │
         ▼
[butler-cli binary]
  prints: "Calendar access granted."
```

---

## 6. Behavioral Memory Write Pipeline

```
[Intervention Engine] receives InteractionOutcome.dismissed
         │
         ▼
[Reinforcement Scorer]
  computes new tolerance: 72 - 2 = 70
  computes trigger last-fired: now
         │ (async write request)
         ▼
[Learning System]
  BEGIN TRANSACTION (SQLite)
    UPDATE behavior_profile SET tolerance_score = 70
    UPDATE trigger_history SET last_fired = now, fire_count_7d = fire_count_7d + 1
      WHERE trigger_type = 'downloads_clutter'
    INSERT INTO interactions (timestamp, trigger_type, outcome, session_id)
      VALUES (now, 'downloads_clutter', 'dismissed', session_id)
    --- check: fire_count for this trigger in last 3 interactions
    SELECT COUNT(*) FROM interactions
      WHERE trigger_type = 'downloads_clutter'
        AND outcome = 'dismissed'
        AND timestamp > (now - 7 days)
    --- if count >= 3:
    INSERT INTO suppressed_triggers (trigger_type, suppressed_at, suppressed_until, reason)
      VALUES ('downloads_clutter', now, now + 7 days, 'auto_3x_dismiss')
  COMMIT
         │
         ▼
[Learning System] publishes profileChangedPublisher
         │
         ▼
[Reinforcement Scorer] cache invalidated (next score uses fresh profile)
[Context Analyzer] cache invalidated (suppressed trigger list refreshed)
```

---

## 7. Conversation Context Management Pipeline

```
[Claude Integration Layer] has completed turn #21
         │
         ▼
  conversation_turns_in_window > 20?
         │ NO → continue normally
         │ YES
         ▼
  background summarization task starts:
         │
         ▼
  Claude API call (low priority, background):
    prompt: "Summarize the following conversation in 3 sentences for context continuity."
    input: turns 1–10 (oldest)
         │
         ▼
  Summary returned (≈200 tokens)
         │
         ▼
[Learning System]
  INSERT INTO memory_summaries (created_at, summary, token_count)
    VALUES (now, summary_text, 200)
  DELETE FROM conversations WHERE id IN (oldest 10 turns)
         │
         ▼
  Next Claude API call includes:
    system_prompt: "...Prior context: [summary text]..."
    messages: [recent 10 turns verbatim]
```

---

## 8. Automation Execution Pipeline (Tier 3)

```
USER voice: "Move all PDF files from Downloads to Documents/PDFs/"
         │
         ▼
[Claude Integration Layer]
  response: "I'll move 23 PDF files from Downloads to Documents/PDFs/.
             Shall I proceed?"
  emits: ConfirmationRequired event
         │
         ▼
[Visualization Engine]
  shows confirmation dialog with file count and destination
  (buttons: Confirm / Modify Plan / Cancel)
         │
USER: clicks [Confirm]
         │
         ▼
[Automation Execution Layer]
  receives: MoveFiles action request (list of 23 source URLs, destination URL)
         │
         ▼
  pre-execution log:
  INSERT INTO action_log (timestamp, action_type, params, status='pending')
         │
         ▼
  execute (serialized, not concurrent):
    for each PDF:
      FileManager.default.moveItem(at: source, to: destination)
         │ failure on any file? → log, skip, continue
         │
         ▼
  register undo handler:
    { for each moved file: FileManager.default.moveItem(at: dest, to: source) }
    undo expires after 30 seconds
         │
         ▼
  update log:
  UPDATE action_log SET status='completed', result_json=... WHERE id=...
         │
         ▼
[Visualization Engine]
  setState(.success)
  shows: "23 PDFs moved. [Undo ◄] 28s"
         │
30 seconds pass
         │
  undo handler deallocated — action is permanent
```

---

## 9. App Launch Pipeline

```
User opens Butler.app (or LaunchAgent starts it)
         │
         ▼
[AppDelegate.applicationDidFinishLaunching]
  NSApp.setActivationPolicy(.accessory)  // no dock icon
         │
         ▼
[Permission & Security Manager] initializes
  reads saved permission state from config.json
  queries system permission statuses (AV, EventKit, AX)
  resolves active tier
  generates session token → writes ~/.butler/run/.auth (0600)
         │
         ▼
[CLI Controller Module] starts socket server
  binds ~/.butler/run/butler.sock (0600)
  starts accepting connections (background actor)
         │
         ▼
[Learning System] opens SQLite database
  runs PRAGMA integrity_check
  runs any pending migrations
         │
         ▼
[Reinforcement Scorer] loads BehaviorProfile from [Learning System]
         │
         ▼
[Activity Monitor] initializes at current permission tier
  starts NSWorkspace observer
  starts idle time polling
  (conditionally) starts Downloads FSEvents watcher (Tier 2)
         │
         ▼
[Context Analyzer] subscribes to activityPublisher
         │
         ▼
[Visualization Engine] creates Glass Chamber window
  NSPanel initialized and positioned
  WKWebView loads pulse.html
  setState(.idle)
         │
         ▼
[Voice System] initializes (no microphone yet — opened per push-to-talk)
         │
         ▼
[Intervention Engine] subscribes to ContextAnalyzer publisher
         │
         ▼
Butler fully operational
  Time from launch to ready: target <2 seconds
```

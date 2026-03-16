# PRD-15: BUTLER — Modular Architecture Specification

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering

---

## 1. Architecture Principles

- **Module isolation:** Each module owns its domain. No module reaches into another module's internals.
- **Explicit contracts:** All inter-module communication is through defined typed interfaces.
- **Fail independently:** A module failure degrades only its feature set; it must not crash other modules.
- **Permission-gated initialization:** Modules above Tier 0 do not initialize until the relevant permission is granted.
- **No shared mutable state:** State is owned by exactly one module. Other modules receive copies or events.
- **Async by default:** All cross-module calls are async. No blocking calls on the main thread.

---

## 2. Module Registry

| # | Module | Swift Type | Communication Pattern |
|---|--------|-----------|----------------------|
| 1 | Activity Monitor | `ActivityMonitor` (actor) | Publisher (Combine) |
| 2 | Context Analyzer | `ContextAnalyzer` (actor) | Request/Response + Publisher |
| 3 | Learning System | `LearningSystem` (actor) | Request/Response |
| 4 | Reinforcement Scorer | `ReinforcementScorer` (actor) | Request/Response |
| 5 | Intervention Engine | `InterventionEngine` (actor) | Publisher (decisions) |
| 6 | Claude Integration Layer | `ClaudeIntegrationLayer` (actor) | Async streaming |
| 7 | Voice System | `VoiceSystem` (actor) | Publisher (amplitude) + async |
| 8 | Visualization Engine | `VisualizationEngine` (MainActor) | Publisher subscription |
| 9 | Automation Execution Layer | `AutomationExecutionLayer` (actor) | Request/Response |
| 10 | Permission & Security Manager | `PermissionSecurityManager` (actor) | Publisher + synchronous read |
| 11 | CLI Controller Module | `CLIController` (actor) | Async socket I/O |

---

## 3. Module Specifications

---

### Module 1: Activity Monitor

**Responsibility:** Observe macOS system signals within the user's granted permission tier. Publish activity events to subscribers. No reasoning, no decisions.

**Initialization condition:** Tier 1 permission granted. Lower tiers: module starts in passive stub mode (publishes empty signals).

**Inputs:**
- macOS system events (NSWorkspace notifications, FSEvents, IOHIDSystem, AXUIElement)
- `PermissionSecurityManager` — current active tier

**Outputs:**
- `Publisher<ActivitySignal, Never>` — stream of activity events

**ActivitySignal types:**
```swift
enum ActivitySignal {
    case activeAppChanged(app: AppInfo)
    case browserDomainChanged(domain: String?)
    case downloadsCountChanged(count: Int, oldestFileDays: Int)
    case idleTimeChanged(seconds: TimeInterval)
    case calendarEventActiveChanged(isActive: Bool)
    case appSwitchBurst(count: Int, within: TimeInterval)
    case screenSleepStateChanged(sleeping: Bool)
    case videoCallStateChanged(active: Bool)
    case fullscreenStateChanged(active: Bool)
}
```

**Resource budget:**
- CPU idle: <0.5%
- CPU active (all signals): <1.5%
- RAM: <20 MB
- Poll interval (idle detection): 10 seconds
- FSEvents batch latency: 5 seconds

**Prohibited behaviors:**
- Must not read file contents
- Must not read calendar event titles or descriptions
- Must not read browser page content or DOM
- Must not persist data (owns no database)

---

### Module 2: Context Analyzer

**Responsibility:** Receive activity signals, evaluate them against a rule set, and produce `InterventionCandidate` events when conditions are met.

**Initialization condition:** None — runs in all tiers, but produces no candidates unless activity signals flow.

**Inputs:**
- `ActivityMonitor.publisher` — activity signal stream
- `LearningSystem.suppressedTriggers()` — which triggers are suppressed
- Rule set from `~/.butler/config/rules.json` (user-configurable, default rules bundled)

**Outputs:**
- `Publisher<InterventionCandidate, Never>` — candidates for the Intervention Engine

**Rule evaluation:**
```swift
struct TriggerRule: Codable {
    let id: String
    let conditions: [Condition]     // All must match (AND)
    let baseWeight: Double          // 0.0–1.0
    let cooldownHours: Double
    let templateID: String
    let minTier: Int
}
```

Rules are evaluated on every incoming `ActivitySignal` from a subscriber callback. Evaluation is O(rules × signals per second) — rules are limited to a maximum of 50 and kept simple (no nested logic). Complex reasoning is delegated to Claude.

**Prohibited behaviors:**
- Must not make decisions about whether to fire a suggestion
- Must not access Claude API
- Must not modify the behavioral profile

---

### Module 3: Learning System

**Responsibility:** Own the SQLite behavioral database. Read and write behavioral profile, interaction history, suppressed triggers, and conversation summaries. Serve read queries from other modules.

**Initialization condition:** Always initialized. Database is encrypted and created on first run.

**Inputs:**
- `InterventionEngine` interaction outcome events (engaged, dismissed, ignored, suppressed)
- `CLIController` history queries and clear commands
- `ReinforcementScorer` write-back requests

**Outputs:**
- `BehaviorProfile` — on request
- `[InteractionRecord]` — history queries
- `[SuppressedTrigger]` — suppressed trigger list
- `[ConversationSummary]` — compressed conversation context

**Database ownership:** Module 3 is the only module that reads from or writes to `butler.db`. No other module accesses the database directly.

**Schema:** See PRD-02 for full schema. Module 3 owns migrations.

**Prohibited behaviors:**
- Must not expose raw SQLite connection to other modules
- Must not delete records without explicit user authorization (except automatic rotation of logs >90 days)

---

### Module 4: Reinforcement Scorer

**Responsibility:** Calculate and update the user's tolerance score, frequency decay values, and per-trigger last-fired timestamps. Does not own storage — writes back via Module 3.

**Initialization condition:** Always initialized.

**Inputs:**
- Interaction outcomes from `InterventionEngine`
- Current `BehaviorProfile` from `LearningSystem`

**Outputs:**
- Updated `BehaviorProfile` (written via `LearningSystem`)
- `InterventionScore` for a given candidate (synchronous read path)

**Scoring formula:**
```swift
func score(candidate: InterventionCandidate, profile: BehaviorProfile) -> Double {
    let contextWeight = candidate.baseWeight
    let userTolerance = Double(profile.toleranceScore) / 100.0
    let timeModifier  = timeOfDayModifier(profile: profile)
    let decayFactor   = frequencyDecay(triggerType: candidate.triggerType, profile: profile)
    return contextWeight * userTolerance * timeModifier * decayFactor
}
```

**Tolerance update deltas:**
| Outcome | Delta |
|---------|-------|
| Engaged | +3 |
| Dismissed | -2 |
| Ignored (no response in 30s) | -1 |
| Never-ask suppression | -1 |

Tolerance is clamped to [0, 100]. Score of 0 means no proactive suggestions fire. Users can reset via `butler reset learning`.

**Prohibited behaviors:**
- Must not query Claude API
- Must not make delivery decisions (only scores)

---

### Module 5: Intervention Engine

**Responsibility:** Receive `InterventionCandidate` events, apply the scoring function, evaluate suppression conditions, and if threshold is met, coordinate delivery of the suggestion to Visualization Engine and Voice System.

**Initialization condition:** Always initialized.

**Inputs:**
- `ContextAnalyzer.publisher` — intervention candidates
- `ReinforcementScorer.score()` — score for candidate
- `PermissionSecurityManager.isSuppressed()` — is current context suppressed?
- `LearningSystem.suppressedTriggers()` — which trigger types are suppressed

**Outputs:**
- `Publisher<InterventionDecision, Never>` — approved interventions for delivery
- Outcome events back to `ReinforcementScorer` after user response

**Decision flow:**
```swift
func evaluate(_ candidate: InterventionCandidate) async {
    guard !learningSystem.isSuppressed(candidate.triggerType) else { return }
    guard !permissionManager.isCurrentContextSuppressed() else { return }

    let profile = await learningSystem.currentProfile()
    let score = reinforcementScorer.score(candidate: candidate, profile: profile)

    guard score >= threshold else { return } // 0.65 default
    guard enforceCooldown(for: candidate.triggerType) else { return }
    guard enforceCap() else { return }        // max 3 per hour

    await deliver(candidate)
}
```

**Frequency cap:** 3 interventions per rolling 60-minute window. Tracked in memory; not persisted.

**Prohibited behaviors:**
- Must not bypass suppression checks under any condition except `butler trigger --force`
- Must not fire more than 3 interventions per hour
- Must not fire during any suppressed context

---

### Module 6: Claude Integration Layer

**Responsibility:** Manage all communication with the Claude API. Build system prompts from personality config and behavioral context. Handle streaming responses. Manage conversation context window.

**Initialization condition:** API key present in Keychain.

**Inputs:**
- User message (from Voice System transcription or CLI `speak` command)
- `PersonalityConfig` — from config file
- `BehaviorProfile` summary — from Learning System
- Conversation history (recent 10 turns, summaries for older)

**Outputs:**
- `AsyncThrowingStream<String, Error>` — streaming response tokens
- Completed response string
- Token usage metrics

**System prompt construction:**
```swift
func buildSystemPrompt(personality: PersonalityConfig, profile: BehaviorProfileSummary) -> String
```

Prompt is constructed fresh per request. No prompt caching on the client side (Anthropic prompt caching is handled server-side).

**Context window management:**
- Last 10 turns: verbatim
- Turns 11–50: compressed to summary via Claude call (background, low priority)
- Turns 51+: not sent; summarized

**Error handling:**
- `URLError.notConnectedToInternet`: return offline error; do not retry
- `HTTPError.rateLimited (429)`: exponential backoff (1s, 2s, 4s, max 3 retries)
- `HTTPError.serverError (5xx)`: exponential backoff, same
- `HTTPError.unauthorized (401)`: surface API key error to user; do not retry

**Prohibited behaviors:**
- Must not log or persist raw user messages beyond conversation history
- Must not send file contents, file paths, or calendar event text to the API
- Must not send full activity logs to the API — only summarized behavioral profile

---

### Module 7: Voice System

**Responsibility:** Manage STT (speech-to-text) and TTS (text-to-speech) pipelines. Publish real-time amplitude for animation sync. Own microphone session lifecycle.

**Initialization condition:** Microphone and speech recognition permissions granted.

**STT inputs:**
- Hardware microphone (AVAudioEngine)
- Push-to-talk keypress events (from AppDelegate global hotkey)
- Wake word detections (CoreML model, if enabled)

**STT outputs:**
- `Publisher<String, Never>` — partial transcriptions (for UI display)
- `AsyncThrowingStream<String, Error>` — final transcriptions (for Claude dispatch)

**TTS inputs:**
- Response text from `ClaudeIntegrationLayer`

**TTS outputs:**
- Audio output (speakers)
- `Publisher<Float, Never>` — real-time amplitude (0.0–1.0) at 60 fps → fed to Visualization Engine

**STT pipeline:**
```
Microphone → AVAudioEngine → AVAudioPCMBuffer
→ SFSpeechAudioBufferRecognitionRequest
→ SFSpeechRecognizer (on-device)
→ partialResultPublisher / finalResultPublisher
```

**TTS pipeline:**
```
Text → AVSpeechUtterance (or ElevenLabsClient)
→ AVSpeechSynthesizer
→ AVAudioEngine tap
→ amplitude extraction (RMS of PCM buffer)
→ amplitudePublisher (60 fps)
```

**Microphone session rules:**
- Microphone is active ONLY during active STT session (push-to-talk held or wake word detected)
- Microphone releases immediately after STT finalizes
- Indicator light on MacBook is therefore active only during listening

**Prohibited behaviors:**
- Must not record audio to disk
- Must not keep microphone session open between STT invocations
- Must not stream audio to any external service (ElevenLabs TTS sends text, not audio)

---

### Module 8: Visualization Engine

**Responsibility:** Drive the Pulse State Machine and the Glass Chamber UI. Subscribe to amplitude and state signals. Render the correct visual output.

**Thread constraint:** `@MainActor` — all UI updates on main thread.

**Initialization condition:** Always initialized.

**Inputs:**
- `InterventionEngine.publisher` — state transitions (Idle→Thinking→Speaking etc.)
- `VoiceSystem.amplitudePublisher` — 60 fps amplitude float
- `PermissionSecurityManager.suppressionPublisher` — for dimming on suppressed state
- User interactions (Glass Chamber UI events)

**Outputs:**
- UI state (SwiftUI view updates)
- WKWebView JavaScript calls (`setState`, `setAmplitude`)

**Pulse State Machine:**
```swift
enum PulseState {
    case idle, listening, thinking, speaking
    case concerned, alert, success, creative
}
```

Transitions are validated — only valid transitions are permitted. Invalid transitions are silently ignored (no crash).

**Valid transitions:**
```
idle        → listening, thinking
listening   → thinking, idle
thinking    → speaking, concerned, idle
speaking    → idle, success
concerned   → alert, idle
alert       → idle
success     → idle
creative    → speaking, idle
```

**Animation control:** State changes are sent to WKWebView via `evaluateJavaScript("window.setState('\(state.rawValue)')")`. Amplitude is throttled to 30fps when GPU load is high.

**Prohibited behaviors:**
- Must not block main thread for more than 8ms (one frame at 120fps)
- Must not trigger UI updates from background threads

---

### Module 9: Automation Execution Layer

**Responsibility:** Execute authorized file system operations, AppleScript, and Shortcuts. Maintain action log. Provide undo capability.

**Initialization condition:** Tier 3 permission granted.

**Inputs:**
- Execution requests from `ClaudeIntegrationLayer` (user-confirmed actions)
- Execution requests from `CLIController` (`butler speak "organize files"`)

**Outputs:**
- `ActionResult` — success/failure with description
- Undo registration (for reversible actions)

**Execution safety protocol:**
1. Every action is serialized — no concurrent file operations
2. Action is logged BEFORE execution
3. Reversible actions register undo handler (30-second window)
4. Non-reversible actions require double confirmation

**Action types:**
```swift
enum ButlerAction {
    case moveFile(source: URL, destination: URL)
    case renameFile(url: URL, newName: String)
    case createFolder(at: URL)
    case trashFile(url: URL)          // NOT permanent delete
    case openApplication(bundleID: String)
    case closeApplication(bundleID: String)
    case runAppleScript(source: String, approved: Bool)
    case triggerShortcut(name: String)
    case draftEmail(to: String, subject: String, body: String)
}
```

**AppleScript safety:**
- Scripts must be shown to user and explicitly approved before execution
- Timeout: 10 seconds per script
- No shell commands allowed in AppleScript (`do shell script` is blocked via regex check before approval)

**Prohibited behaviors:**
- Must not execute any action without prior confirmation
- Must not permanently delete files (trash only)
- Must not run AppleScript that contains `do shell script`
- Must not execute concurrent file operations

---

### Module 10: Permission & Security Manager

**Responsibility:** Enforce permission tiers at runtime. Validate that module requests conform to the active tier. Maintain audit log. Manage IPC authentication.

**Initialization condition:** Always initialized. Runs before all other modules.

**Inputs:**
- System permission status (queried via AVFoundation, EventKit, etc.)
- User permission grants/revocations (from Settings UI or CLI)

**Outputs:**
- `Publisher<PermissionTier, Never>` — current active tier
- `Publisher<Bool, Never>` — current suppression state (for any hardcoded kill switch)
- `isSuppressed() -> Bool` — synchronous read for hot path

**Suppression hierarchy (checked in order):**
```
1. Active video call → SUPPRESS (cannot be overridden)
2. Screen sharing → SUPPRESS (cannot be overridden)
3. Fullscreen app → SUPPRESS (cannot be overridden)
4. macOS Focus mode → SUPPRESS (cannot be overridden)
5. Gaming mode → SUPPRESS (cannot be overridden)
6. Global Mute (user) → SUPPRESS
7. Focus Mode (BUTLER, user) → SUPPRESS suggestions only
8. Quiet Hours → SUPPRESS suggestions only
9. Sensitivity threshold → reduce score (not suppress)
```

Items 1–5 are hardcoded and cannot be changed by user settings or AI logic. Items 6–9 are user-configurable.

**IPC authentication:** Generates session token at launch, writes to `~/.butler/run/.auth` (0600). Validates token on every CLI request. See PRD-12 for full IPC auth design.

**Prohibited behaviors:**
- Must not disable suppression rules 1–5 under any circumstances
- Must not expose internal permission state to Claude API requests

---

### Module 11: CLI Controller Module

**Responsibility:** Operate the Unix domain socket server. Accept CLI connections, dispatch to command handlers, return responses. Bridge the `butler` CLI binary to all other modules.

**Initialization condition:** Always initialized (CLI should be usable even in Tier 0).

**Inputs:**
- CLI connections via Unix domain socket (`~/.butler/run/butler.sock`)
- Commands from `butler-cli` binary

**Outputs:**
- JSON responses over socket (see PRD-12 for protocol)
- Streams (for `butler speak`, `butler logs --follow`)

**Command dispatch:**
```swift
func route(_ request: CLIRequest) async -> CLIResponse {
    switch request.command {
    case "config.set": return await ConfigCommandHandler(config: configStore).handle(request)
    case "speak":      return await SpeakCommandHandler(claude: claudeLayer, voice: voiceSystem).handle(request)
    case "status":     return await StatusCommandHandler(modules: moduleRegistry).handle(request)
    // ...
    }
}
```

**Prohibited behaviors:**
- Must not grant any capability that the current permission tier does not allow
- Must not block the main thread
- Must not accept connections from non-matching UID processes

---

## 4. Module Dependency Graph

```
ActivityMonitor ──────────────────────────────┐
                                              │ ActivitySignal
                                              ▼
LearningSystem ◄────── ReinforcementScorer ◄── InterventionEngine ◄── ContextAnalyzer
       │                                          │
       │ BehaviorProfile                          │ InterventionDecision
       ▼                                          ▼
ClaudeIntegrationLayer ──────────────────► VisualizationEngine
       │                                          ▲
       │ response stream                          │ amplitude (60fps)
       ▼                                          │
VoiceSystem ──────────────────────────────────────┘
       │
       │ transcription
       ▼
ClaudeIntegrationLayer

PermissionSecurityManager ──► (all modules check before activating)

CLIController ──► (dispatches to any module via command handlers)

AutomationExecutionLayer ◄── ClaudeIntegrationLayer (action requests)
                         ◄── CLIController (speak command → action)
```

---

## 5. Cross-Cutting Concerns

### 5.1 Logging
Every module logs to a shared structured logger (`ButlerLogger`). Log format:
```
2026-03-03 14:32:01.042 INFO  [InterventionEngine] Score: 0.697 — firing trigger: downloads_clutter
```
Log level per module is configurable via `butler config set logging.<module> debug|info|warn|error`.

### 5.2 Error Propagation
- Module failures are logged and reported to `StatusCommandHandler`
- Modules do not propagate errors to other modules (fail silently in degraded mode)
- Fatal errors (database inaccessible, API key invalid) surface to the user via Glass Chamber UI

### 5.3 Memory Management
- No module holds strong references to other modules (use weak references or actors with explicit ownership)
- Module registry is owned by `AppDelegate`
- Modules communicate via Combine publishers (no direct method calls between peers, except CLIController dispatching to handlers)

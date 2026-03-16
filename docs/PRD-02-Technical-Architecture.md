# PRD-02: BUTLER — Technical Architecture Document

**Version:** 2.0
**Date:** 2026-03-03
**Status:** Draft — Updated for 11-Module Architecture + CLI/IPC
**Owner:** Engineering

> **Cross-references:** PRD-15 (full module specs) | PRD-12 (CLI/IPC architecture) | PRD-16 (data flow diagrams) | PRD-17 (resource management) | PRD-18 (anti-intrusiveness) | PRD-19 (edge cases)

---

## 1. Architecture Philosophy

- **Local-first:** All behavioral data, memory, and processing remain on device
- **API-minimal:** Claude API receives only what is necessary; no raw user data
- **Modular:** 11 explicitly bounded modules; each independently replaceable
- **Permission-gated:** No module activates above its granted permission tier
- **Resource-conscious:** BUTLER targets <2% idle CPU, <150MB RAM baseline
- **CLI-native:** All product functions are accessible via the `butler` CLI binary
- **Fail-independent:** Module failure degrades its feature set only; does not cascade

---

## 2. 11-Module Architecture Overview

BUTLER is composed of 11 explicitly bounded modules. Each module owns its domain, communicates through defined interfaces, and fails independently. Full module specifications are in PRD-15.

| # | Module | Type | Communication |
|---|--------|------|--------------|
| 1 | Activity Monitor | `actor` | Combine Publisher |
| 2 | Context Analyzer | `actor` | Combine Publisher |
| 3 | Learning System | `actor` | Request/Response (async) |
| 4 | Reinforcement Scorer | `actor` | Request/Response (sync read) |
| 5 | Intervention Engine | `actor` | Combine Publisher |
| 6 | Claude Integration Layer | `actor` | AsyncThrowingStream |
| 7 | Voice System | `actor` | Publisher + async |
| 8 | Visualization Engine | `@MainActor` | Publisher subscription |
| 9 | Automation Execution Layer | `actor` | Request/Response |
| 10 | Permission & Security Manager | `actor` | Publisher + sync read |
| 11 | CLI Controller Module | `actor` | Unix socket I/O |

### 2.1 High-Level System Diagram

```
                         $ butler <cmd>
                               │
                    [11] CLI Controller Module
                         (Unix socket server)
                               │ dispatches to modules
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                           BUTLER.app                                 │
│                                                                      │
│  [10] Permission & Security Manager ──────────────────────────────┐  │
│       (enforces tiers, hardcoded kill switches, IPC auth)         │  │
│                                ▼ (all modules check)              │  │
│  [1] Activity Monitor → [2] Context Analyzer → [5] Intervention   │  │
│       (signals)            (rule engine)          Engine          │  │
│                                                       │           │  │
│                           [4] Reinforcement           │           │  │
│                               Scorer ◄────────────────┤           │  │
│                                 │ scores               │           │  │
│                           [3] Learning System ◄────────┤           │  │
│                               (SQLite owner)    outcomes│           │  │
│                                                       │           │  │
│  [6] Claude Integration Layer ◄───────────────────────┘           │  │
│       (API client, prompt builder, context mgmt)                  │  │
│            │ token stream                                          │  │
│  ┌─────────┴──────────────────────┐                               │  │
│  │                                │                               │  │
│  ▼                                ▼                               │  │
│  [7] Voice System            [8] Visualization Engine             │  │
│      (STT + TTS)                  (Pulse + Glass Chamber UI)      │  │
│      │ amplitude (60fps)          ▲                               │  │
│      └────────────────────────────┘                               │  │
│                                                                      │
│  [9] Automation Execution Layer                                      │
│      (file ops, AppleScript, Shortcuts — Tier 3 only)                │
└──────────────────────────────────────────────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │    Claude API        │
                    │  (api.anthropic.com) │
                    └─────────────────────┘
```

### 2.2 Binary Structure

```
Butler.app/
└── Contents/
    └── MacOS/
        ├── Butler          ← GUI + all 11 modules
        └── butler-cli      ← CLI binary (thin IPC client only)

/usr/local/bin/butler       ← symlink → Butler.app/Contents/MacOS/butler-cli
~/.butler/run/butler.sock   ← Unix domain socket (runtime only)
~/.butler/run/.auth         ← Session token (runtime only, 0600)
```

---

## 3. Module Specifications

### 3.1 Glass Chamber UI Module

**Technology:** Swift + SwiftUI (macOS 14+)
**Framework dependencies:** AppKit (window management), AVFoundation (audio), Metal/WebKit (animation)

**Key Components:**
```
GlassChamberWindow
├── NSVisualEffectView (blur + frosted glass)
├── PulseRenderView (Metal or WKWebView)
│   └── AnimationStateMachine
├── ConversationPanelView
│   ├── MessageListView
│   ├── InputBarView
│   └── VoiceWaveformView
├── QuickControlsBar
│   ├── MicToggleButton
│   ├── MuteButton
│   ├── FocusModeButton
│   └── CollapseButton
└── SettingsPanelView (expandable)
    ├── PersonalityTab
    ├── VoiceTab
    ├── PermissionsTab
    ├── AutomationTab
    ├── PrivacyTab
    └── AppearanceTab
```

**Window Management:**
- `NSPanel` with `.nonActivatingPanel` behavior (doesn't steal focus)
- `NSWindowLevel.floating` or `.statusBar` (configurable)
- Custom `NSWindowController` for drag, pin, and collapse logic
- Auto-hide timer with configurable delay (default: 30 seconds after last interaction)

---

### 3.2 Pulse Rendering Engine

**Option A — Metal (Recommended for production):**
```swift
struct PulseRenderer {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState

    // State inputs
    var currentState: PulseState
    var amplitude: Float      // 0.0 - 1.0 from TTS
    var urgency: Float        // 0.0 - 1.0 from Decision Engine
    var confidence: Float     // 0.0 - 1.0 from response quality

    func render(in view: MTKView) { ... }
}
```

**Option B — WebGL via WKWebView (Recommended for Phase 1):**
- Three.js shader scene embedded in WKWebView
- Swift ↔ JS bridge via `WKScriptMessageHandler`
- JSON state messages passed at 60fps
- Easier to iterate visually without Xcode recompilation

**Audio-Reactive Pipeline:**
```swift
// AVAudioEngine tap on TTS output bus
AVAudioEngine → AVAudioMixerNode → amplitudeTap(bufferSize: 1024) → {
    amplitude = RMS(buffer)
    PulseRenderer.amplitude = amplitude
}
```

---

### 3.3 Voice System Module

**STT Pipeline:**
```
Microphone → AVAudioEngine → SpeechRecognitionRequest →
SFSpeechAudioBufferRecognitionRequest → SFSpeechRecognizer →
Transcription → OrchestrationLayer
```

**Push-to-Talk:**
- Global hotkey via `CGEventTap` or `NSEvent.addGlobalMonitorForEvents`
- Default: `⌘ Space` (configurable)
- Hold = record, release = transcribe

**Wake Word (Tier 2+):**
- Local wake word detection via lightweight CoreML model
- "Hey Butler" or custom 2-word phrase
- Activates STT pipeline without button press

**TTS Pipeline:**
```
Claude Response Text → PersonalityEngine.formatSpeech() →
AVSpeechSynthesizer OR ElevenLabsClient →
AVAudioEngine output → AmplitudeAnalyzer → PulseRenderer
```

---

### 3.4 Activity Monitor Module

**Permission Tier 1:**
```swift
class ActivityMonitor {
    // NSWorkspace observer — no special entitlements
    func observeActiveApp() -> AnyPublisher<AppInfo, Never> {
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
    }

    // Browser domain extraction via Accessibility API
    func observeBrowserDomain() -> AnyPublisher<String?, Never> { ... }
}
```

**Permission Tier 2:**
```swift
extension ActivityMonitor {
    // File system via FSEvents (Downloads folder watcher)
    func watchDownloadsFolder() -> FSEventStream { ... }

    // Idle detection via IOHIDSystem
    func idleTime() -> TimeInterval { ... }

    // Duplicate file detection (filename + size hash)
    func scanForDuplicates(in folder: URL) async -> [DuplicateGroup] { ... }

    // Calendar event presence (EventKit — no content)
    func hasActiveCalendarEvent() -> Bool { ... }
}
```

**Domain Extraction (Browser):**
```swift
// Uses Accessibility API to read address bar text
// Only extracts host component (domain), not path or query params
func extractBrowserDomain(app: NSRunningApplication) -> String? {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    // Traverse AX tree to URL bar
    // Parse URLComponents(string: urlString)?.host only
}
```

---

### 3.5 Context Analyzer Module

```swift
class ContextAnalyzer {
    struct ContextEvent {
        let trigger: TriggerType
        let weight: Double       // 0.0–1.0
        let metadata: [String: Any]
        let timestamp: Date
    }

    // Rule engine — evaluates active signals against trigger ruleset
    func evaluate(signals: ActivitySignals) -> [ContextEvent] { ... }

    // Combines events into intervention candidate
    func buildCandidate(from events: [ContextEvent]) -> InterventionCandidate? { ... }
}
```

**Rule Definition Format (JSON-configurable):**
```json
{
  "rule_id": "downloads_clutter",
  "trigger_type": "file_system",
  "conditions": [
    { "signal": "downloads_file_count", "operator": "gte", "value": 100 },
    { "signal": "oldest_file_age_days", "operator": "gte", "value": 7 }
  ],
  "base_weight": 0.7,
  "cooldown_hours": 4,
  "suggestion_template": "downloads_clutter_v1"
}
```

---

### 3.6 Intervention Decision Engine

```swift
class InterventionDecisionEngine {
    let THRESHOLD: Double = 0.65

    func score(candidate: InterventionCandidate, memory: BehaviorProfile) -> Double {
        let contextWeight = candidate.baseWeight
        let userTolerance = Double(memory.toleranceScore) / 100.0
        let timeModifier = timeOfDayModifier()
        let decayFactor = frequencyDecay(for: candidate.triggerType, history: memory)

        return contextWeight * userTolerance * timeModifier * decayFactor
    }

    func shouldIntervene(score: Double) -> Bool {
        return score >= THRESHOLD
    }

    func timeOfDayModifier() -> Double {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 22...23, 0...6: return 0.5   // Late night / early morning
        case 9...17: return 1.0            // Work hours
        default: return 0.75
        }
    }

    func frequencyDecay(for type: TriggerType, history: BehaviorProfile) -> Double {
        guard let lastFired = history.lastTrigger[type] else { return 1.0 }
        let hoursSince = Date().timeIntervalSince(lastFired) / 3600
        return min(1.0, hoursSince / 4.0)  // Full weight restored after 4 hours
    }
}
```

---

### 3.7 Behavioral Memory Store

**Storage:** SQLite via GRDB.swift (lightweight, no server)
**Encryption:** SQLCipher (AES-256 at rest)

**Schema:**
```sql
-- Interaction history
CREATE TABLE interactions (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL,
    trigger_type TEXT NOT NULL,
    outcome TEXT NOT NULL,  -- 'engaged', 'dismissed', 'ignored', 'suppressed'
    context_snapshot TEXT,  -- JSON
    session_id TEXT
);

-- Behavioral profile (single row, updated continuously)
CREATE TABLE behavior_profile (
    id INTEGER PRIMARY KEY DEFAULT 1,
    tolerance_score INTEGER DEFAULT 50,
    productivity_hours TEXT,  -- JSON array of hour ranges
    preferred_formality INTEGER DEFAULT 3,
    humor_acceptance INTEGER DEFAULT 3,
    last_updated TEXT
);

-- Trigger suppression rules
CREATE TABLE suppressed_triggers (
    trigger_type TEXT PRIMARY KEY,
    suppressed_at TEXT,
    suppressed_until TEXT,  -- NULL = permanent
    reason TEXT  -- 'user_explicit', 'auto_3x_dismiss', 'cooldown'
);

-- Per-trigger last-fired timestamps
CREATE TABLE trigger_history (
    trigger_type TEXT PRIMARY KEY,
    last_fired TEXT,
    fire_count_7d INTEGER DEFAULT 0
);

-- Conversation history (for context continuity)
CREATE TABLE conversations (
    id INTEGER PRIMARY KEY,
    session_id TEXT,
    timestamp TEXT,
    role TEXT,  -- 'user' or 'assistant'
    content TEXT,
    summary_chunk_id INTEGER
);

-- Compressed summaries for long-term memory
CREATE TABLE memory_summaries (
    id INTEGER PRIMARY KEY,
    created_at TEXT,
    summary TEXT,
    token_count INTEGER
);
```

**Reinforcement Scoring Update:**
```swift
func updateToleranceScore(outcome: InteractionOutcome) {
    switch outcome {
    case .engaged:   profile.toleranceScore = min(100, profile.toleranceScore + 3)
    case .dismissed: profile.toleranceScore = max(0,   profile.toleranceScore - 2)
    case .ignored:   profile.toleranceScore = max(0,   profile.toleranceScore - 1)
    case .suppressed: break  // No score change for explicit suppression
    }
}
```

---

### 3.8 Claude API Client

```swift
class ClaudeAPIClient {
    private let apiKey: String
    private let model = "claude-opus-4-6"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    func sendMessage(
        systemPrompt: String,
        messages: [Message],
        behaviorProfile: BehaviorProfileSummary,
        stream: Bool = true
    ) async throws -> AsyncThrowingStream<String, Error> { ... }

    // Builds system prompt from personality config + behavioral summary
    func buildSystemPrompt(
        personality: PersonalityConfig,
        profile: BehaviorProfileSummary
    ) -> String { ... }
}
```

**Context Window Management:**
- Conversation history compressed to summaries after 20 turns
- Summaries stored in `memory_summaries` table
- Recent 10 turns passed verbatim; prior context as summary
- Behavioral profile passed as structured JSON in system prompt

**Request Payload:**
```json
{
  "model": "claude-opus-4-6",
  "max_tokens": 1024,
  "stream": true,
  "system": "You are Alfred, a refined digital assistant...\n\nUser Profile:\n{behavioral_summary_json}",
  "messages": [
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "..." }
  ]
}
```

---

### 3.9 Personality Engine

```swift
struct PersonalityConfig: Codable {
    var name: String = "Butler"
    var formality: Int = 3        // 1-5
    var proactivity: Int = 3      // 1-5
    var humor: Int = 2            // 1-5
    var directness: Int = 4       // 1-5
    var voicePreset: VoicePreset = .calmAmerican
    var customPromptAddition: String = ""
}

class PersonalityEngine {
    func buildSystemPrompt(config: PersonalityConfig, profile: BehaviorProfileSummary) -> String {
        """
        You are \(config.name), a refined digital assistant serving a professional user.
        Formality: \(formalityDescriptor(config.formality))
        Humor: \(humorDescriptor(config.humor))
        Directness: \(directnessDescriptor(config.directness))
        Proactivity level: \(config.proactivity)/5

        Current context:
        - User tolerance score: \(profile.toleranceScore)/100
        - Focus state: \(profile.focusState)
        - Time of day: \(profile.timeOfDay)
        - Active app: \(profile.activeApp)

        Rules:
        - Keep unprompted responses under 2 sentences
        - Always offer dismissal
        - Never judge user behavior
        - \(config.customPromptAddition)
        """
    }
}
```

---

### 3.10 Automation Execution Layer (Module 9)

```swift
actor AutomationExecutionLayer {
    // All actions logged before execution
    func execute(action: ButlerAction, confirmed: Bool) async throws {
        guard confirmed else { throw ExecutionError.notConfirmed }
        logBeforeExecution(action: action)  // Log BEFORE — not after

        switch action {
        case .moveFile(let source, let destination):
            try FileManager.default.moveItem(at: source, to: destination)
            registerUndo(source: source, destination: destination, window: 30)

        case .openApp(let bundleID):
            try await NSWorkspace.shared.open([], withApplicationAt: bundleURL, ...)

        case .runAppleScript(let script):
            guard !script.contains("do shell script") else {
                throw ExecutionError.forbiddenOperation("shell commands via AppleScript")
            }
            try await AppleScriptExecutor.execute(script, timeout: 10.0)

        case .triggerShortcut(let name):
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            NSWorkspace.shared.open(URL(string: "shortcuts://run-shortcut?name=\(encoded)")!)
        }
    }
}
```

---

### 3.11 CLI Controller Module (Module 11)

> Full specification: PRD-12 (CLI Module Architecture)

```swift
// Socket server — accepts butler-cli connections
actor CLIController {
    private let socketPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".butler/run/butler.sock").path

    func start() async throws {
        let server = UnixSocketServer(path: socketPath, permissions: 0o600)
        try await server.start()
        for await connection in server.connections {
            Task { await handleConnection(connection) }
        }
    }

    private func handleConnection(_ connection: UnixSocketConnection) async {
        defer { connection.close() }
        let request = try await decodeRequest(connection)
        guard authenticate(request) else { return sendAuthError(connection) }
        let response = await commandRouter.route(request)
        try await connection.writeLine(encode(response))
    }
}
```

**IPC protocol:** Newline-delimited JSON over Unix domain socket at `~/.butler/run/butler.sock` (permissions: 0600).

**Authentication:** Session token at `~/.butler/run/.auth` (0600), generated fresh at each app launch.

---

## 4. Inter-Module API Contracts

### 4.1 Activity Monitor → Context Analyzer
```swift
struct ActivitySignals {
    let activeApp: AppInfo?           // Bundle ID, name, category
    let browserDomain: String?        // Host only
    let downloadsFileCount: Int?
    let idleSeconds: TimeInterval
    let hasActiveCalendarEvent: Bool
    let recentAppSwitches: [AppSwitch]
    let timestamp: Date
}
```

### 4.2 Context Analyzer → Decision Engine
```swift
struct InterventionCandidate {
    let triggerType: TriggerType
    let baseWeight: Double
    let suggestedTemplate: String
    let metadata: [String: Any]
    let expiresAt: Date
}
```

### 4.3 Decision Engine → Glass Chamber UI
```swift
struct InterventionRequest {
    let message: String           // Formatted suggestion text
    let voiceScript: String       // Text for TTS (may differ from displayed)
    let targetState: PulseState   // Pulse animation state
    let priority: InterventionPriority
    let dismissOptions: [DismissOption]
}
```

### 4.4 Claude API → Voice + UI
```swift
// Streaming token delivery
AsyncThrowingStream<StreamEvent, Error>

enum StreamEvent {
    case text(String)             // Incremental text token
    case done(String)             // Full completed response
    case error(Error)
}
```

---

## 5. Technology Stack Summary

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| App Framework | Swift + SwiftUI | Native performance, Accessibility API, deep system integration |
| Window | NSPanel + AppKit | Non-activating floating panel |
| Animation | Metal (prod) / WebGL/Three.js (dev) | Performance / iteration speed |
| STT | Apple SFSpeechRecognizer | On-device, private |
| Wake word | CoreML custom model | On-device, no network |
| TTS | AVSpeechSynthesizer + ElevenLabs | Native default, premium option |
| AI | Claude API (streaming) | Reasoning quality |
| Local DB | SQLite via GRDB.swift | Lightweight, encrypted |
| DB Encryption | SQLCipher | AES-256 at rest |
| Embeddings | MLX or llama.cpp local | For memory similarity search |
| Build | Xcode, Swift Package Manager | Standard macOS toolchain |
| Testing | XCTest + Swift Testing | Unit and integration |

---

## 6. Performance Targets

| Metric | Target |
|--------|--------|
| Idle CPU usage | <2% |
| Idle RAM usage | <150 MB |
| Voice response latency (STT→Claude→TTS first word) | <1.5 seconds |
| Animation frame rate | 60 fps |
| App launch time | <2 seconds |
| Context trigger evaluation cycle | <100ms |
| File operation confirmation roundtrip | <500ms |
| SQLite query time (profile read) | <10ms |

---

## 7. Build & Distribution

- **Distribution:** Direct download + Mac App Store (separate builds due to sandbox constraints)
- **Direct build:** Full Accessibility API access, AppleScript, FSEvents
- **App Store build:** Sandboxed, reduced automation capability, Tier 3 features unavailable
- **Auto-update:** Sparkle framework for direct distribution builds
- **Code signing:** Apple Developer ID (direct) + App Store distribution cert
- **Notarization:** Required for direct distribution on macOS 15+

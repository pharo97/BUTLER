# BUTLER — Comprehensive Build Plan v2

**Date:** 2026-03-06
**Status:** Active
**Synthesizes:** PRD-02, PRD-15, PRD-18 architecture + Perplexity AI/learning research
**Working directory:** `/Users/farah/Dev/projects/ButlerAi/`

---

## Current State

**Phase 0 (COMPLETE ✅):** Glass Chamber visual shell

| File | Status |
|------|--------|
| `Butler/App/ButlerApp.swift` | ✅ Complete |
| `Butler/App/AppDelegate.swift` | ✅ Complete |
| `Butler/UI/GlassChamber/GlassChamberPanel.swift` | ✅ Complete |
| `Butler/UI/GlassChamber/GlassChamberView.swift` | ✅ Complete (Phase 1 test controls) |
| `Butler/UI/GlassChamber/PulseWebView.swift` | ✅ Complete |
| `Butler/Modules/VisualizationEngine/VisualizationEngine.swift` | ✅ Complete |
| `Butler/Resources/pulse.html` | ✅ Complete (JARVIS 3D orb, solar flares, 5-layer system) |

**Module coverage:** 1 of 11 modules partially built (Module 8: VisualizationEngine).
**Everything below is what we need to build.**

---

## Revised Phase Roadmap

Maps Perplexity's research recommendations to the PRD-15 11-module architecture:

| Phase | Weeks | Modules Built | Theme | Key Deliverable |
|-------|-------|---------------|-------|-----------------|
| **0** | Done | M8 (partial) | Visual Shell | Glass Chamber + Pulse animation |
| **1** | 1–3 | M7, M6, M3 (minimal) | Voice + Claude | Push-to-talk, streaming Claude, SQLite conversations |
| **2** | 4–5 | M3 (full), M10 | Behavioral Memory + Safety | Full schema, Bayesian tolerance, kill switches |
| **3** | 6–7 | M4, M5 | Online Learning + Intervention | ReinforcementScorer, InterventionEngine wired |
| **4** | 8–9 | M1, M2 | Context Awareness | ActivityMonitor, ContextAnalyzer, rule engine |
| **5** | 10–11 | M5 + M8 (full) | Full Intervention Loop | End-to-end: context → score → Claude → voice → pulse |
| **6** | 12–13 | M11, M9 | CLI + Automation | butler binary, Unix socket, Tier 3 actions |
| **7** | 14–16 | All | Polish + Distribution | Performance, code signing, DMG, Homebrew |

---

## Complete Target File Structure

```
ButlerAi/
├── project.yml
├── .gitignore
├── docs/                                  ← PRD docs (existing)
└── Butler/
    ├── App/
    │   ├── ButlerApp.swift                ✅ DONE
    │   └── AppDelegate.swift              ✅ DONE
    │
    ├── UI/
    │   └── GlassChamber/
    │       ├── GlassChamberPanel.swift    ✅ DONE
    │       ├── GlassChamberView.swift     ✅ DONE
    │       └── PulseWebView.swift         ✅ DONE
    │
    ├── Resources/
    │   └── pulse.html                     ✅ DONE
    │
    └── Modules/
        ├── VisualizationEngine/
        │   └── VisualizationEngine.swift  ✅ DONE (partial — needs subscription wiring)
        │
        ├── VoiceSystem/                   ← Phase 1
        │   ├── VoiceSystem.swift          Actor façade + state machine
        │   ├── VoiceInputController.swift SFSpeechRecognizer + AVAudioEngine
        │   └── VoiceOutputController.swift AVSpeechSynthesizer + amplitude tap
        │
        ├── ClaudeIntegration/             ← Phase 1
        │   ├── ClaudeIntegrationLayer.swift Actor façade + streaming
        │   ├── ClaudeAPIClient.swift      URLSession streaming client
        │   ├── PromptBuilder.swift        System prompt construction
        │   ├── ContextWindowManager.swift Last-10-turns + summary rotation
        │   └── KeychainService.swift      API key read/write/delete
        │
        ├── LearningSystem/                ← Phase 2 (minimal in Phase 1)
        │   ├── LearningSystem.swift       Actor façade + sole DB owner
        │   ├── DatabaseManager.swift      GRDB setup, migrations, encryption
        │   ├── BehaviorProfile.swift      Profile model + GRDB record
        │   ├── InteractionRecord.swift    Interaction model + GRDB record
        │   └── ConversationStore.swift    Conversation CRUD + summary rotation
        │
        ├── ReinforcementScorer/           ← Phase 3
        │   ├── ReinforcementScorer.swift  Actor façade + score calculation
        │   ├── ToleranceModel.swift       Bayesian Beta + leaky bucket decay
        │   └── TimeOfDayModifier.swift    Hour-based multiplier table
        │
        ├── InterventionEngine/            ← Phase 3–5
        │   ├── InterventionEngine.swift   Actor façade + evaluate() loop
        │   ├── InterventionCandidate.swift Candidate model
        │   └── FrequencyCapTracker.swift  Rolling 60-min window counter
        │
        ├── ActivityMonitor/               ← Phase 4
        │   ├── ActivityMonitor.swift      Actor façade + NSWorkspace observations
        │   ├── AppTracker.swift           Frontmost app tracking
        │   ├── BrowserDomainExtractor.swift AX API → domain only
        │   ├── IdleTimeTracker.swift      IOHIDSystem idle query
        │   ├── DownloadsFolderWatcher.swift FSEvents watcher
        │   └── VideoCallDetector.swift    Bundle ID + audio capture check
        │
        ├── ContextAnalyzer/               ← Phase 4
        │   ├── ContextAnalyzer.swift      Actor façade + rule evaluator
        │   ├── TriggerRule.swift          Rule model (Codable, JSON-loadable)
        │   └── RuleLoader.swift           Load from ~/.butler/config/rules.json
        │
        ├── PermissionSecurityManager/     ← Phase 2
        │   ├── PermissionSecurityManager.swift Actor + suppression hierarchy
        │   ├── KillSwitchMonitor.swift    Hardcoded checks (video call, screen share, fullscreen, Focus)
        │   └── PermissionTier.swift       Tier 0–3 enum + capability table
        │
        ├── AutomationExecutionLayer/      ← Phase 6
        │   ├── AutomationExecutionLayer.swift Actor + serialized action queue
        │   ├── ButlerAction.swift         Action enum (move, rename, trash, AppleScript…)
        │   └── ActionLogger.swift         Pre-execution audit log + undo registration
        │
        └── CLIController/                 ← Phase 6
            ├── CLIController.swift        Actor + Unix socket server
            ├── CommandRouter.swift        Command string → handler dispatch
            └── CommandHandlers/
                ├── SpeakHandler.swift
                ├── StatusHandler.swift
                ├── ConfigHandler.swift
                └── ResetHandler.swift
```

---

## Phase 1: Voice + Claude (Weeks 1–3)

**Goal:** User can hold push-to-talk, speak, and receive a streaming Claude response read aloud. Pulse reacts to all states.

### Module 7: VoiceSystem

**`VoiceInputController.swift`**
```swift
import AVFoundation
import Speech

actor VoiceInputController {

    private let recognizer   = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var audioEngine  = AVAudioEngine()
    private var request:       SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Partial results (for live transcription display)
    let partialPublisher  = PassthroughSubject<String, Never>()
    // Final result (triggers Claude dispatch)
    let finalPublisher    = PassthroughSubject<String, Never>()

    func startListening() throws {
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.request?.append(buf)
        }
        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let result else { return }
            if result.isFinal {
                self?.finalPublisher.send(result.bestTranscription.formattedString)
                Task { await self?.stopListening() }
            } else {
                self?.partialPublisher.send(result.bestTranscription.formattedString)
            }
        }
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        recognitionTask?.cancel()
        request = nil
        recognitionTask = nil
    }
}
```

**`VoiceOutputController.swift`**
```swift
import AVFoundation
import Combine

actor VoiceOutputController: NSObject {

    private let synthesizer = AVSpeechSynthesizer()
    private let engine      = AVAudioEngine()

    // Published to VisualizationEngine at ~60fps during TTS
    let amplitudePublisher = PassthroughSubject<Double, Never>()

    func speak(_ text: String, voice: AVSpeechSynthesisVoice? = nil) async throws {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate  = 0.52
        // Amplitude tap wired in makeNSView — synthesizer outputs to engine bus
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // Call this from AVAudioEngine output tap setup
    nonisolated func extractAmplitude(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let rms = (0..<frameCount).reduce(0.0) { acc, i in
            acc + Double(channelData[i] * channelData[i])
        }
        return min(1.0, sqrt(rms / Double(frameCount)) * 8.0)   // scale to 0–1
    }
}
```

**`VoiceSystem.swift`** (actor façade)
```swift
import Combine

@MainActor
final class VoiceSystem {

    private let input  = VoiceInputController()
    private let output = VoiceOutputController()

    var amplitudePublisher: AnyPublisher<Double, Never> {
        output.amplitudePublisher.eraseToAnyPublisher()
    }
    var finalTranscriptionPublisher: AnyPublisher<String, Never> {
        input.finalPublisher.eraseToAnyPublisher()
    }

    func beginListening() async throws {
        try await input.startListening()
    }

    func endListening() async {
        await input.stopListening()
    }

    func speak(_ text: String) async throws {
        try await output.speak(text)
    }

    func stopSpeaking() async {
        await output.stopSpeaking()
    }
}
```

**Global hotkey wiring in `AppDelegate.swift`:**
```swift
// Add to applicationDidFinishLaunching:
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
    // ⌘ Space = push-to-talk (configurable)
    if event.modifierFlags.contains(.command) && event.keyCode == 49 {
        Task { @MainActor in try? await self?.voiceSystem.beginListening() }
    }
}
NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
    if event.keyCode == 49 {
        Task { @MainActor in await self?.voiceSystem.endListening() }
    }
}
```

---

### Module 6: Claude Integration Layer

**`KeychainService.swift`**
```swift
import Security

struct KeychainService {
    static let service = "com.butler.app"
    static let account = "anthropic_api_key"

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    static func load() throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else { throw KeychainError.notFound }
        return key
    }

    enum KeychainError: Error { case saveFailed(OSStatus), notFound }
}
```

**`ClaudeAPIClient.swift`**
```swift
import Foundation

actor ClaudeAPIClient {
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model   = "claude-opus-4-6"

    func streamResponse(
        messages: [[String: String]],
        systemPrompt: String,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var request = URLRequest(url: baseURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                let body: [String: Any] = [
                    "model": model,
                    "max_tokens": 1024,
                    "stream": true,
                    "system": systemPrompt,
                    "messages": messages
                ]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { return }
                guard http.statusCode == 200 else {
                    continuation.finish(throwing: ClaudeError.httpError(http.statusCode))
                    return
                }

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))
                    guard jsonStr != "[DONE]",
                          let data = jsonStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String,
                          type == "content_block_delta",
                          let delta = json["delta"] as? [String: Any],
                          let text = delta["text"] as? String
                    else { continue }
                    continuation.yield(text)
                }
                continuation.finish()
            }
        }
    }

    enum ClaudeError: Error { case httpError(Int) }
}
```

**`ContextWindowManager.swift`**
```swift
// Manages last-10-turns verbatim + summary rotation for older turns
actor ContextWindowManager {
    private var messages: [(role: String, content: String)] = []
    private let maxVerbatim = 10

    func append(role: String, content: String) {
        messages.append((role, content))
    }

    func buildAPIMessages() -> [[String: String]] {
        // Last maxVerbatim turns verbatim; older turns collapsed to summaries
        let verbatim = messages.suffix(maxVerbatim)
        return verbatim.map { ["role": $0.role, "content": $0.content] }
    }
}
```

---

### Phase 1: Wire VisualizationEngine to Voice

**Update `AppDelegate.swift`** — subscribe amplitude + state:
```swift
// After creating engine and voiceSystem:
voiceSystem.amplitudePublisher
    .receive(on: RunLoop.main)
    .sink { [weak engine] amp in engine?.setAmplitude(amp) }
    .store(in: &cancellables)

// State transitions:
// VoiceSystem begins → engine.setState(.listening)
// STT final result   → engine.setState(.thinking)
// Claude first token → engine.setState(.speaking) — wait for TTS to start
// TTS complete       → engine.setState(.idle)
```

---

### Phase 1: SQLite Setup (Minimal — conversations only)

Add GRDB.swift via Swift Package Manager:
- Package URL: `https://github.com/groue/GRDB.swift`
- From: `6.0.0`

**`DatabaseManager.swift`** (minimal Phase 1 schema):
```swift
import GRDB

final class DatabaseManager {
    let dbQueue: DatabaseQueue

    static let path: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".butler/data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("butler.db")
    }()

    init() throws {
        dbQueue = try DatabaseQueue(path: Self.path.path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_conversations") { db in
            try db.create(table: "conversations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }
}
```

---

## Phase 2: Behavioral Memory + Safety (Weeks 4–5)

### Module 3: LearningSystem (Full Schema)

**Extended migration — add to `DatabaseManager.swift`:**
```swift
migrator.registerMigration("v2_behavioral_memory") { db in
    // Full behavioral profile
    try db.create(table: "behavior_profile") { t in
        t.primaryKey("id", .integer)
        t.column("tolerance_alpha", .double).notNull().defaults(to: 1.0)
        t.column("tolerance_beta",  .double).notNull().defaults(to: 1.0)
        t.column("productivity_hours", .text)       // JSON [8,9,...,17]
        t.column("preferred_formality", .integer).defaults(to: 3)
        t.column("humor_acceptance",    .integer).defaults(to: 3)
        t.column("last_updated", .datetime)
    }

    // Per-context Bayesian tolerance (Perplexity recommendation)
    // Key: app_bundle_id + trigger_type combination
    try db.create(table: "context_tolerance") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("context_key", .text).notNull().unique()   // "com.apple.Xcode::downloads_clutter"
        t.column("alpha", .double).notNull().defaults(to: 1.0)
        t.column("beta",  .double).notNull().defaults(to: 1.0)
        t.column("interaction_count", .integer).defaults(to: 0)
        t.column("last_interaction", .datetime)
    }

    // Interaction log
    try db.create(table: "interactions") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("timestamp", .datetime).notNull()
        t.column("trigger_type", .text).notNull()
        t.column("outcome", .text).notNull()             // engaged|dismissed|ignored|suppressed
        t.column("context_key", .text)
        t.column("score_at_fire", .double)
        t.column("session_id", .text)
    }

    // Trigger suppression list
    try db.create(table: "suppressed_triggers") { t in
        t.column("trigger_type", .text).primaryKey()
        t.column("suppressed_at", .datetime)
        t.column("suppressed_until", .datetime)          // NULL = permanent
        t.column("reason", .text)                        // user_explicit|auto_3x|cooldown
    }

    // Per-trigger last-fired + 7-day fire count
    try db.create(table: "trigger_history") { t in
        t.column("trigger_type", .text).primaryKey()
        t.column("last_fired", .datetime)
        t.column("fire_count_7d", .integer).defaults(to: 0)
    }

    // Long-term memory summaries
    try db.create(table: "memory_summaries") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("created_at", .datetime)
        t.column("summary", .text)
        t.column("token_count", .integer)
    }
}
```

**`ToleranceModel.swift`** (Perplexity's Bayesian Beta recommendation):
```swift
/// Bayesian Beta distribution model for UserTolerance.
///
/// Instead of a simple integer delta system, we maintain alpha (successes)
/// and beta (failures) counts. The tolerance score is the Beta mean:
///   tolerance = alpha / (alpha + beta)
///
/// Cold start: alpha=1, beta=1 → tolerance=0.5 (uniform prior)
/// Per-context keying: one ToleranceModel per (app_bundle_id + trigger_type) pair
/// Global fallback: when no context model exists, use global model
///
/// Source: Perplexity research recommendation (2026-03-06)
struct ToleranceModel: Codable {

    var alpha: Double   // Engagement successes
    var beta:  Double   // Dismissals / ignores (weighted)

    /// Initialises at uniform prior (0.5 tolerance)
    init(alpha: Double = 1.0, beta: Double = 1.0) {
        self.alpha = alpha
        self.beta  = beta
    }

    /// Beta distribution mean: the effective tolerance score (0.0 – 1.0)
    var tolerance: Double {
        alpha / (alpha + beta)
    }

    /// Confidence: how many effective observations do we have?
    /// Low confidence → fall back toward global average
    var confidence: Double {
        min(1.0, (alpha + beta - 2.0) / 10.0)  // reaches 1.0 after ~10 observations
    }

    /// Update based on interaction outcome.
    ///
    /// Deltas (from Perplexity research + Bayesian asymmetry design):
    /// - Engaged:   alpha += 1.0     (clear positive signal)
    /// - Dismissed: beta  += 2.0     (stronger negative — dismiss is explicit rejection)
    /// - Ignored:   beta  += 0.5     (weak negative — may not have seen it)
    /// - Suppressed: no change       (environmental, not preference)
    mutating func update(outcome: InteractionOutcome) {
        switch outcome {
        case .engaged:    alpha += 1.0
        case .dismissed:  beta  += 2.0
        case .ignored:    beta  += 0.5
        case .suppressed: break
        }
    }

    /// Leaky bucket decay: gradually reset toward prior over time.
    /// Call once per session (or once per day via ButlerRuntime wake handler).
    ///
    /// Lambda (λ): controls decay speed. λ=0.02 per session → ~50 sessions to full decay.
    /// This prevents very old interactions from dominating current behavior.
    mutating func decay(lambda: Double = 0.02) {
        // Shrink both counts toward 1.0 (the uniform prior) proportionally
        alpha = 1.0 + (alpha - 1.0) * (1.0 - lambda)
        beta  = 1.0 + (beta  - 1.0) * (1.0 - lambda)
    }

    /// Blend with global model when context model has low confidence.
    /// Uses confidence as interpolation weight.
    func blended(with global: ToleranceModel) -> Double {
        let c = confidence
        return tolerance * c + global.tolerance * (1.0 - c)
    }
}

enum InteractionOutcome: String, Codable {
    case engaged    = "engaged"
    case dismissed  = "dismissed"
    case ignored    = "ignored"
    case suppressed = "suppressed"
}
```

**`LearningSystem.swift`** (actor façade):
```swift
actor LearningSystem {

    private let db: DatabaseManager

    // In-memory global tolerance model for fast access
    private var globalTolerance = ToleranceModel()

    init(db: DatabaseManager) {
        self.db = db
    }

    // MARK: - Tolerance

    /// Returns blended tolerance for a given context key.
    /// Falls back to global average if no context history exists (cold start).
    func tolerance(for contextKey: String) async -> Double {
        let contextModel = (try? await db.contextToleranceModel(for: contextKey)) ?? ToleranceModel()
        return contextModel.blended(with: globalTolerance)
    }

    func recordOutcome(_ outcome: InteractionOutcome, contextKey: String, triggerType: String, scoreAtFire: Double) async {
        // Update global model
        globalTolerance.update(outcome: outcome)

        // Update per-context model
        var contextModel = (try? await db.contextToleranceModel(for: contextKey)) ?? ToleranceModel()
        contextModel.update(outcome: outcome)
        try? await db.saveContextToleranceModel(contextModel, for: contextKey)

        // Log interaction
        try? await db.logInteraction(
            triggerType: triggerType,
            outcome: outcome.rawValue,
            contextKey: contextKey,
            scoreAtFire: scoreAtFire
        )
    }

    func decayTolerance() async {
        // Called on session start / wake (by ButlerRuntime)
        globalTolerance.decay()
        try? await db.decayAllContextToleranceModels()
    }

    // MARK: - Suppression

    func isSuppressed(_ triggerType: String) async -> Bool {
        (try? await db.isTriggerSuppressed(triggerType)) ?? false
    }

    func suppressTrigger(_ triggerType: String, until: Date?, reason: String) async {
        try? await db.suppressTrigger(triggerType, until: until, reason: reason)
    }

    // MARK: - Conversation history

    func saveMessage(role: String, content: String, sessionID: String) async {
        try? await db.saveConversation(role: role, content: content, sessionID: sessionID)
    }

    func recentMessages(limit: Int = 10) async -> [(role: String, content: String)] {
        (try? await db.recentConversations(limit: limit)) ?? []
    }
}
```

---

### Module 10: PermissionSecurityManager

**`KillSwitchMonitor.swift`**
```swift
import AppKit
import AVFoundation

/// Detects all Priority 1–5 hardcoded suppression conditions.
/// These cannot be overridden by user settings or AI logic.
actor KillSwitchMonitor {

    func isAnyKillSwitchActive() -> Bool {
        isVideoCallActive()
        || isScreenSharing()
        || isFullscreen()
        || isFocusModeActive()
    }

    private func isVideoCallActive() -> Bool {
        let videoCallBundles: Set<String> = [
            "us.zoom.xos",              // Zoom
            "com.microsoft.teams",       // Teams
            "com.apple.facetime",        // FaceTime
            "com.google.chrome",         // Meet (via browser — check audio separately)
            "com.cisco.webexmeetings",   // Webex
            "com.loom.desktop",          // Loom
        ]
        // Check if a known video call app is frontmost AND capturing audio
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmostApp.bundleIdentifier
        else { return false }
        let bundleMatch = videoCallBundles.contains(bundleID)
        // Additional: check if any process is capturing from mic
        let audioCapturing = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        return bundleMatch && audioCapturing
    }

    private func isScreenSharing() -> Bool {
        // CGWindowListCopyWindowInfo to detect screen recording session
        // or check if com.apple.screensharing process is running
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == "com.apple.screensharing" }
    }

    private func isFullscreen() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return false }
        // Check if frontmost app's window has NSWindowStyleMask.fullScreen
        for window in NSApplication.shared.windows {
            if window.isOnActiveSpace && window.styleMask.contains(.fullScreen) {
                return true
            }
        }
        return false
    }

    private func isFocusModeActive() -> Bool {
        // macOS Focus mode does not have a public API; best effort:
        // Read from ~/Library/DoNotDisturb/DB/Assertions.json
        // or check if any Focus mode schedule is active via private API
        // Phase 2 implementation: polling ~30s, file-based
        false   // TODO: implement Focus mode detection in Phase 2
    }
}
```

**`PermissionSecurityManager.swift`**
```swift
import Combine

actor PermissionSecurityManager {

    private let killSwitch = KillSwitchMonitor()
    private var suppressionSubject = CurrentValueSubject<Bool, Never>(false)

    var suppressionPublisher: AnyPublisher<Bool, Never> {
        suppressionSubject.eraseToAnyPublisher()
    }

    /// Fast synchronous suppression check — used in intervention hot path
    nonisolated func isSuppressed() -> Bool {
        suppressionSubject.value
    }

    /// Poll suppression state (call from a background timer)
    func updateSuppressionState() async {
        let suppressed = await killSwitch.isAnyKillSwitchActive()
        suppressionSubject.send(suppressed)
    }

    // MARK: - Permission tier

    enum PermissionTier: Int, Codable {
        case passive  = 0   // No observation
        case app      = 1   // Active app + browser domain
        case context  = 2   // FS, calendar, idle, browser URL
        case automation = 3 // File ops, AppleScript, Shortcuts
    }

    private(set) var activeTier: PermissionTier = .passive
}
```

---

## Phase 3: Online Learning + Intervention Engine (Weeks 6–7)

### Module 4: ReinforcementScorer

**`ReinforcementScorer.swift`**
```swift
actor ReinforcementScorer {

    private let learningSystem: LearningSystem

    init(learningSystem: LearningSystem) {
        self.learningSystem = learningSystem
    }

    /// Calculate intervention score.
    ///
    /// Formula (PRD-15 + Bayesian tolerance from Perplexity research):
    ///   score = contextWeight × userTolerance × timeModifier × decayFactor
    ///
    /// Threshold for firing: 0.65
    func score(candidate: InterventionCandidate) async -> Double {
        let contextKey    = candidate.contextKey   // app_bundle_id::trigger_type
        let tolerance     = await learningSystem.tolerance(for: contextKey)
        let timeModifier  = TimeOfDayModifier.current()
        let decayFactor   = candidate.decayFactor  // Set by ContextAnalyzer from trigger_history

        return candidate.baseWeight * tolerance * timeModifier * decayFactor
    }
}

struct TimeOfDayModifier {
    static func current() -> Double {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 22...23, 0...6: return 0.40  // Very late night / very early morning
        case 7...8:          return 0.70  // Early morning
        case 9...17:         return 1.00  // Core work hours
        case 18...21:        return 0.75  // Evening
        default:             return 0.75
        }
    }
}
```

### Module 5: InterventionEngine

**`FrequencyCapTracker.swift`**
```swift
/// Enforces max 3 interventions per rolling 60-minute window.
/// Tracked in memory — not persisted (intentional: resets on restart).
struct FrequencyCapTracker {
    private var firings: [Date] = []
    private let windowSeconds: TimeInterval = 3600
    private let maxPerWindow: Int = 3

    mutating func canFire() -> Bool {
        let now = Date()
        firings.removeAll { now.timeIntervalSince($0) > windowSeconds }
        return firings.count < maxPerWindow
    }

    mutating func recordFiring() {
        firings.append(Date())
    }
}
```

**`InterventionEngine.swift`**
```swift
import Combine

actor InterventionEngine {

    private let contextAnalyzer:   ContextAnalyzer
    private let scorer:            ReinforcementScorer
    private let learningSystem:    LearningSystem
    private let permissionManager: PermissionSecurityManager

    private var capTracker = FrequencyCapTracker()
    private var cooldowns:  [String: Date] = [:]          // trigger_type → last fired
    private var cancellables: Set<AnyCancellable> = []

    let decisionsPublisher = PassthroughSubject<InterventionCandidate, Never>()

    init(
        contextAnalyzer: ContextAnalyzer,
        scorer: ReinforcementScorer,
        learningSystem: LearningSystem,
        permissionManager: PermissionSecurityManager
    ) {
        self.contextAnalyzer   = contextAnalyzer
        self.scorer            = scorer
        self.learningSystem    = learningSystem
        self.permissionManager = permissionManager
    }

    func start() async {
        await contextAnalyzer.candidatesPublisher
            .sink { [weak self] candidate in
                Task { await self?.evaluate(candidate) }
            }
            .store(in: &cancellables)
    }

    private func evaluate(_ candidate: InterventionCandidate) async {
        // 1. Hardcoded kill switches
        guard await !permissionManager.isSuppressed() else { return }

        // 2. User-suppressed triggers
        guard await !learningSystem.isSuppressed(candidate.triggerType) else { return }

        // 3. Score threshold
        let score = await scorer.score(candidate: candidate)
        guard score >= 0.65 else { return }

        // 4. Per-trigger cooldown
        if let lastFired = cooldowns[candidate.triggerType] {
            let hoursSince = Date().timeIntervalSince(lastFired) / 3600
            guard hoursSince >= candidate.cooldownHours else { return }
        }

        // 5. Frequency cap (3 per hour)
        guard capTracker.canFire() else { return }
        capTracker.recordFiring()
        cooldowns[candidate.triggerType] = Date()

        // 6. Publish approved candidate for delivery
        decisionsPublisher.send(candidate)
    }

    /// Called by UI when user responds to an intervention
    func recordOutcome(_ outcome: InteractionOutcome, for candidate: InterventionCandidate, scoreAtFire: Double) async {
        await learningSystem.recordOutcome(
            outcome,
            contextKey: candidate.contextKey,
            triggerType: candidate.triggerType,
            scoreAtFire: scoreAtFire
        )

        // Auto-suppress after 3x dismiss
        if outcome == .dismissed {
            let key = candidate.triggerType
            // TODO: count dismissals in DB and suppress if >= 3
        }
    }
}
```

---

## Phase 4: Context Awareness (Weeks 8–9)

### Module 1: ActivityMonitor

**`ActivityMonitor.swift`**
```swift
import AppKit
import Combine

actor ActivityMonitor {

    let signalPublisher = PassthroughSubject<ActivitySignal, Never>()

    private var permissionTier: PermissionSecurityManager.PermissionTier = .passive
    private var cancellables: Set<AnyCancellable> = []

    func start(tier: PermissionSecurityManager.PermissionTier) async {
        self.permissionTier = tier
        await setupTier1Observers()
        if tier.rawValue >= 2 { await setupTier2Observers() }
    }

    // MARK: - Tier 1 Observers

    private func setupTier1Observers() async {
        // Frontmost app changes (NSWorkspace — no special entitlements)
        NSWorkspace.shared
            .publisher(for: \.frontmostApplication)
            .compactMap { $0 }
            .sink { [weak self] app in
                let info = AppInfo(
                    bundleID:    app.bundleIdentifier ?? "",
                    displayName: app.localizedName ?? "",
                    pid:         app.processIdentifier
                )
                self?.signalPublisher.send(.activeAppChanged(app: info))
            }
            .store(in: &cancellables)

        // Wake/unlock notifications (for ButlerRuntime greeting + decay)
        NotificationCenter.default.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .sink { [weak self] _ in
                // Signal used by ButlerRuntime to trigger wake greeting + tolerance decay
                self?.signalPublisher.send(.screenSleepStateChanged(sleeping: false))
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.signalPublisher.send(.screenSleepStateChanged(sleeping: false))
            }
            .store(in: &cancellables)
    }

    // MARK: - Tier 2 Observers

    private func setupTier2Observers() async {
        // Downloads folder watcher (FSEvents — no special entitlements for user home)
        await DownloadsFolderWatcher.shared.start { [weak self] count, oldestDays in
            self?.signalPublisher.send(.downloadsCountChanged(count: count, oldestFileDays: oldestDays))
        }

        // Idle time polling (10s interval)
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            let idle = IOHIDGetSystemActivityState()  // simplified — see VideoCallDetector impl
            Task { self?.signalPublisher.send(.idleTimeChanged(seconds: idle)) }
        }
    }
}

struct AppInfo {
    let bundleID:    String
    let displayName: String
    let pid:         pid_t
}
```

### Module 2: ContextAnalyzer

**`TriggerRule.swift`**
```swift
struct TriggerRule: Codable {
    let id:               String
    let conditions:       [Condition]     // All must match (AND logic)
    let baseWeight:       Double          // 0.0–1.0
    let cooldownHours:    Double
    let templateID:       String          // Maps to suggestion copy
    let minTier:          Int

    struct Condition: Codable {
        let signal:   String              // e.g. "downloads_file_count"
        let op:       String              // "gte" | "lte" | "eq"
        let value:    Double
    }
}
```

**`ContextAnalyzer.swift`**
```swift
import Combine

actor ContextAnalyzer {

    let candidatesPublisher = PassthroughSubject<InterventionCandidate, Never>()
    private var rules: [TriggerRule] = []
    private var cancellables: Set<AnyCancellable> = []

    // Current observed state — updated on each ActivitySignal
    private var currentBundleID: String = ""
    private var downloadsCount:  Int    = 0
    private var oldestFileDays:  Int    = 0

    func start(activityMonitor: ActivityMonitor, learningSystem: LearningSystem) async {
        rules = RuleLoader.loadDefault()

        await activityMonitor.signalPublisher
            .sink { [weak self] signal in
                Task { await self?.process(signal: signal, learningSystem: learningSystem) }
            }
            .store(in: &cancellables)
    }

    private func process(signal: ActivitySignal, learningSystem: LearningSystem) async {
        // Update state from signal
        switch signal {
        case .activeAppChanged(let app):    currentBundleID = app.bundleID
        case .downloadsCountChanged(let c, let d):
            downloadsCount = c
            oldestFileDays = d
        default: break
        }

        // Evaluate all rules against current state
        for rule in rules {
            guard evaluate(rule) else { continue }
            let contextKey  = "\(currentBundleID)::\(rule.id)"
            let isSuppressed = await learningSystem.isSuppressed(rule.id)
            guard !isSuppressed else { continue }

            let candidate = InterventionCandidate(
                triggerType:  rule.id,
                baseWeight:   rule.baseWeight,
                cooldownHours: rule.cooldownHours,
                contextKey:   contextKey
            )
            candidatesPublisher.send(candidate)
        }
    }

    private func evaluate(_ rule: TriggerRule) -> Bool {
        rule.conditions.allSatisfy { condition in
            let value: Double
            switch condition.signal {
            case "downloads_file_count":    value = Double(downloadsCount)
            case "oldest_file_age_days":    value = Double(oldestFileDays)
            default:                        return false
            }
            switch condition.op {
            case "gte": return value >= condition.value
            case "lte": return value <= condition.value
            case "eq":  return value == condition.value
            default:    return false
            }
        }
    }
}

struct InterventionCandidate {
    let triggerType:   String
    let baseWeight:    Double
    let cooldownHours: Double
    let contextKey:    String
    var decayFactor:   Double = 1.0   // Set by ContextAnalyzer from trigger_history
}
```

---

## Phase 5: Full Intervention Loop Wiring (Weeks 10–11)

This is the phase that connects everything into a single cohesive flow.

### ButlerRuntime (from Perplexity — slots into AppDelegate)

```swift
/// Handles session lifecycle events: wake, unlock, session start.
/// Triggers: tolerance decay, greet-on-wake, context watcher start.
///
/// Perplexity recommendation: NSWorkspace session notifications are the
/// right hook for adaptive learning decay — reset state on session boundaries.
@MainActor
final class ButlerRuntime {
    let learningSystem:    LearningSystem
    let voiceSystem:       VoiceSystem
    let visualEngine:      VisualizationEngine

    func applicationDidFinishLaunching() {
        // Decay tolerance once on launch (session boundary)
        Task { await learningSystem.decayTolerance() }

        // Subscribe to wake/unlock for greeting
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    private func handleWake() {
        Task {
            await learningSystem.decayTolerance()
            // Optional: brief greeting pulse on wake
            visualEngine.setState(.idle)
        }
    }
}
```

### Full Module Wiring in AppDelegate

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // All 11 modules
    let db                  = try! DatabaseManager()
    let learningSystem:       LearningSystem
    let permissionManager:    PermissionSecurityManager
    let activityMonitor:      ActivityMonitor
    let contextAnalyzer:      ContextAnalyzer
    let scorer:               ReinforcementScorer
    let interventionEngine:   InterventionEngine
    let claudeLayer:          ClaudeIntegrationLayer
    let voiceSystem:          VoiceSystem
    let visualEngine:         VisualizationEngine     // ← already built

    // Glass Chamber
    var panel:              GlassChamberPanel?
    var cancellables:       Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Boot sequence (order matters — permission manager first)
        Task {
            await permissionManager.updateSuppressionState()

            await activityMonitor.start(tier: .passive)   // upgrade as permissions granted
            await contextAnalyzer.start(
                activityMonitor: activityMonitor,
                learningSystem: learningSystem
            )
            await interventionEngine.start()

            // Wiring: amplitude → VisualizationEngine
            voiceSystem.amplitudePublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] amp in self?.visualEngine.setAmplitude(amp) }
                .store(in: &cancellables)

            // Wiring: intervention decisions → Claude → Voice → Pulse
            await interventionEngine.decisionsPublisher
                .sink { [weak self] candidate in
                    Task { await self?.handleIntervention(candidate) }
                }
                .store(in: &cancellables)
        }

        // Launch panel
        panel = GlassChamberPanel(engine: visualEngine)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func handleIntervention(_ candidate: InterventionCandidate) async {
        // 1. Visualize thinking
        visualEngine.setState(.thinking)

        // 2. Generate response from Claude
        let apiKey    = (try? KeychainService.load()) ?? ""
        let messages  = await learningSystem.recentMessages()
        let response  = try? await claudeLayer.generateSuggestion(
            candidate: candidate,
            recentMessages: messages,
            apiKey: apiKey
        )
        guard let text = response else {
            visualEngine.setState(.idle); return
        }

        // 3. Speak and animate
        visualEngine.setState(.speaking)
        try? await voiceSystem.speak(text)
        visualEngine.setState(.idle)
    }
}
```

---

## Phase 6: CLI + Distribution (Weeks 12–13)

### Module 11: CLIController (Unix socket)

```swift
// Key setup: add to project.yml as second target
// targets:
//   butler-cli:
//     type: tool
//     platform: macOS
//     sources: [Butler/CLI]

actor CLIController {
    private let socketPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".butler/run/butler.sock").path

    func start() async {
        // Create Unix domain socket
        // Accept connections
        // Authenticate via ~/.butler/run/.auth token
        // Dispatch to CommandRouter
    }
}
```

### Supported CLI commands (Phase 6 target):
```
butler status              → Module health + active tier + last intervention
butler speak "text"        → Inject message into Claude conversation
butler config set key value → Write to ~/.butler/config/butler.json
butler reset learning      → Wipe tolerance models, set all to 0.5
butler trigger list        → Show all suppressed triggers
butler trigger unsuppress <type> → Remove suppression
butler logs --follow       → Stream intervention log
butler mute [--minutes N]  → Mute proactive suggestions
butler unmute              → Clear mute
```

---

## SQLite Augmentation Summary

The Perplexity research revealed that the original PRD-02 schema (single `tolerance_score INTEGER`) is insufficient for per-context adaptive learning. The v2 schema adds:

| Table | Purpose | Perplexity Recommendation |
|-------|---------|--------------------------|
| `behavior_profile` | Global Bayesian alpha/beta | Replace integer tolerance with (α, β) pair |
| `context_tolerance` | Per (app + trigger) Bayesian model | Per-context keying — "don't nag about downloads while coding" |
| `interactions` | Full outcome log with contextKey + scoreAtFire | Feature vector logging for future offline analysis |

**Cold-start handling** (Perplexity): When `context_tolerance` has no row for a context key, fall back to `behavior_profile` global model. This ensures day-1 behavior is reasonable (tolerance = 0.5) rather than erroring or defaulting to always-fire.

**Decay trigger** (Perplexity): Tolerance decay via leaky bucket runs on `NSWorkspace.didWakeNotification` and `sessionDidBecomeActiveNotification` — session boundaries, not wall-clock timers. This is more natural: the system forgets old behavior at the same cadence the user comes back to their computer.

---

## Feature Vector for Future Offline Analysis

Log these fields in `interactions.context_snapshot` (JSON) for future ML training:

```json
{
  "app_bundle_id": "com.apple.Xcode",
  "trigger_type": "downloads_clutter",
  "time_of_day_hour": 14,
  "time_sin": 0.707,
  "time_cos": 0.707,
  "days_since_last_accepted": 3.2,
  "interaction_streak": 2,
  "downloads_count": 127,
  "idle_seconds": 0,
  "score_at_fire": 0.71,
  "outcome": "dismissed"
}
```

This enables future Phase 3+ work: export to CoreML `MLDataTable`, train a `TabularClassifier`, and replace the hand-tuned formula with a learned one — all on-device.

---

## Open Questions (Resolve Before Phase 3)

1. **Focus mode detection**: No public macOS API. Options: (a) poll `~/Library/DoNotDisturb/DB/Assertions.json`; (b) use `DnDControl` private framework (not App Store safe); (c) ask user to set Butler quiet hours instead. **Recommendation: (c) for v1.**

2. **ElevenLabs TTS**: The PRD mentions it as optional. Integration is a network call with text → MP3 response. Implement only if AVSpeechSynthesizer voice quality is rejected in user testing. No architectural change needed — `VoiceOutputController` can swap implementations.

3. **Wake word ("Hey Butler")**: Requires a CoreML classification model (~200KB). Can use `CreateML` with ~50 positive samples. Implement as Phase 4 add-on, not blocking.

4. **GRDB + SQLCipher**: The PRD specifies AES-256 encryption. SQLCipher integration with GRDB requires either `GRDB.swift` + `SQLCipher` SPM packages or the pre-built `GRDBCipher` pod. Confirm SPM compatibility before committing to `project.yml`.

5. **Conversation summary compression**: PRD-15 Module 6 mentions background Claude calls for turn 11–50 summarization. This is a secondary Claude call (low priority, fires when conversation exceeds 10 turns). Implementation is straightforward but requires tracking conversation turn count.

---

## Build Order Summary

```
Week 1:  VoiceInputController + Push-to-talk hotkey wiring
Week 2:  VoiceOutputController + amplitude publisher
Week 3:  ClaudeAPIClient + KeychainService + ContextWindowManager
         → Milestone: Voice ↔ Claude ↔ Pulse fully wired

Week 4:  DatabaseManager migrations v1+v2 + GRDB integration
Week 5:  PermissionSecurityManager + KillSwitchMonitor
         → Milestone: Safety layer + behavioral DB operational

Week 6:  ToleranceModel + ReinforcementScorer
Week 7:  InterventionEngine + FrequencyCapTracker
         → Milestone: Scoring pipeline ready (but no signals yet)

Week 8:  ActivityMonitor (Tier 1 observers: app changes, wake/unlock)
Week 9:  ContextAnalyzer + TriggerRule + RuleLoader + default rules.json
         → Milestone: First end-to-end intervention fires proactively

Week 10: Wire ButlerRuntime + decay on wake + greeting logic
Week 11: Full AppDelegate wiring — all 8 active modules connected
         → Milestone: Full BUTLER working: "Hey, your Downloads is cluttered" fires at the right moment

Week 12: CLIController + Unix socket + basic command handlers
Week 13: AutomationExecutionLayer + Tier 3 actions (Tier 3 permission gate)
         → Milestone: `butler speak "clean my downloads"` works from terminal

Week 14: Performance profiling (target: <2% idle CPU, <150MB RAM)
Week 15: Code signing + notarization pipeline (PRD-14)
Week 16: DMG packaging + Homebrew tap + beta release
```

---

*This plan supersedes the original Phase 1 build plan (`~/.claude/plans/wild-munching-bachman.md`) for all phases beyond the Glass Chamber visual shell.*

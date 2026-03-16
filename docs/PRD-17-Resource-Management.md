# PRD-17: BUTLER — Resource Management Plan

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering

---

## 1. Resource Targets

BUTLER must remain a background citizen. Users should not notice it in Activity Monitor or on their battery health.

| Resource | Idle Target | Active Target | Peak (burst, <5s) | Hard Limit |
|----------|------------|--------------|-------------------|------------|
| CPU (all threads) | <2% | <8% | <25% | 40% |
| RAM (RSS) | <150 MB | <250 MB | <350 MB | 400 MB |
| GPU (for animation) | <3% | <10% | <20% | 30% |
| Disk I/O | <1 MB/min | <5 MB/min | <50 MB/burst | — |
| Network | 0 (idle) | API call only | — | — |
| Battery impact | Low | Low-Medium | Medium | High (triggers throttle) |
| Open file descriptors | <50 | <100 | <150 | 200 |

"Active" = Butler is speaking/processing a Claude response.
"Idle" = Butler running in background, monitoring at Tier 2, no active interaction.

---

## 2. CPU Budget by Module

| Module | Idle Budget | Active Budget | Notes |
|--------|------------|--------------|-------|
| Activity Monitor | 0.3% | 0.5% | NSWorkspace observer is near-zero; FSEvents batched at 5s |
| Context Analyzer | 0.2% | 0.3% | Rule evaluation is lightweight O(rules) |
| Learning System | 0.1% | 0.3% | SQLite writes batched; WAL mode |
| Reinforcement Scorer | 0.05% | 0.1% | Pure computation, no I/O |
| Intervention Engine | 0.1% | 0.2% | Event-driven; almost zero between events |
| Claude Integration Layer | 0.1% | 2.0% | Network I/O during API streaming |
| Voice System (STT) | 0% | 2.5% | Only active during push-to-talk |
| Voice System (TTS) | 0% | 1.5% | Only active during speech output |
| Visualization Engine | 1.0% | 3.0% | Animation render loop |
| Automation Execution Layer | 0% | 0.5% | Only active during file operations |
| Permission & Security Manager | 0.05% | 0.1% | Event-driven |
| CLI Controller Module | 0.1% | 0.3% | Socket I/O; near-zero between CLI calls |
| **Total** | **~2%** | **~8%** | |

---

## 3. RAM Budget by Module

| Module | Baseline RAM | Peak RAM | Notes |
|--------|-------------|---------|-------|
| App framework + SwiftUI | 40 MB | 50 MB | Base cost of SwiftUI app + AppKit |
| WKWebView (Three.js) | 35 MB | 60 MB | WebView has high baseline; Three.js scene |
| SQLite database (GRDB) | 8 MB | 25 MB | WAL file can grow during heavy write bursts |
| Conversation history (in-memory) | 5 MB | 20 MB | Last 10 turns in memory |
| Behavioral profile cache | 1 MB | 2 MB | Small struct |
| Activity Monitor buffers | 3 MB | 8 MB | FSEvents buffer, AX object cache |
| Claude API response buffer | 0 MB | 10 MB | Held only during streaming |
| Voice System (STT) | 5 MB | 30 MB | SFSpeechRecognizer model loaded on first use |
| Voice System (TTS) | 3 MB | 15 MB | AVSpeechSynthesizer + voice data |
| Image assets + UI | 10 MB | 20 MB | Glass Chamber, icons, animations |
| **Total baseline** | **~110 MB** | | |
| **Total active** | | **~250 MB** | |

### 3.1 Memory Pressure Response

BUTLER subscribes to `NSApplication.didReceiveMemoryWarningNotification` and `DispatchSource` memory pressure events.

```swift
// Memory pressure levels and response actions
enum MemoryPressureLevel { case normal, warning, critical }

func handleMemoryPressure(_ level: MemoryPressureLevel) {
    switch level {
    case .warning:
        // Suspend non-essential activity
        activityMonitor.pause()
        conversationCache.trimToLast(turns: 5)
        // Reduce animation quality
        visualizationEngine.setFrameRate(30)

    case .critical:
        // Suspend all background monitoring
        activityMonitor.suspend()
        contextAnalyzer.suspend()
        // Clear all caches
        conversationCache.clear()
        profileCache.invalidate()
        // Reduce animation to 1fps (just show pulse alive)
        visualizationEngine.setFrameRate(1)
    }
}
```

BUTLER reports its reduced state to the user:
- `.warning`: Glass Chamber status shows "Reduced mode — system memory low"
- `.critical`: Pulse dims to minimum, status shows "Suspended — memory pressure"

---

## 4. GPU Resource Management

### 4.1 Frame Rate Adaptation

| Condition | Frame Rate |
|-----------|-----------|
| Active interaction (speaking/thinking) | 60 fps |
| Idle (breathing animation) | 30 fps |
| Battery saver mode (user toggle) | 30 fps |
| On battery power (automatic) | 30 fps |
| Memory pressure | 15 fps |
| Memory pressure critical | 1 fps (heartbeat only) |

```swift
func updateFrameRate() {
    let pluggedIn = ProcessInfo.processInfo.isLowPowerModeEnabled == false
        && powerSource == .external
    let memPressure = currentMemoryPressure

    switch (pluggedIn, memPressure, currentState) {
    case (true, .normal, .speaking), (true, .normal, .thinking):
        webView.evaluateJavaScript("setFrameRate(60)")
    case (false, _, _), (_, .warning, _):
        webView.evaluateJavaScript("setFrameRate(30)")
    case (_, .critical, _):
        webView.evaluateJavaScript("setFrameRate(1)")
    default:
        webView.evaluateJavaScript("setFrameRate(30)")
    }
}
```

### 4.2 WKWebView Optimization

Three.js animation lives in WKWebView. Key optimizations:
- Geometry: SphereGeometry with 32×32 segments (not higher; sufficient for abstract blob)
- Shader: GLSL — no post-processing pipeline; single-pass render
- Background: transparent (no overdraw of the background)
- Antialiasing: off (glass chamber blur provides natural softness)
- `WKWebViewConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true` — required
- `WKWebView.isInspectable = false` — disable Web Inspector in production builds

---

## 5. Disk I/O Management

### 5.1 SQLite Write Optimization

- **WAL mode:** `PRAGMA journal_mode = WAL` — concurrent reads during writes
- **Write batching:** Behavioral profile updates batched with 500ms debounce
- **Synchronous mode:** `PRAGMA synchronous = NORMAL` — safer than OFF, faster than FULL
- **Auto-checkpoint:** WAL auto-checkpointed at 1000 pages or on clean close
- **Indexes:** All query-hot columns indexed (timestamp, trigger_type, session_id)

### 5.2 Log File Management

- Log file max size: 10 MB
- Rotation: on exceeding 10 MB, move to `butler.log.1` (retain 1 prior log)
- Retention: 30 days for activity log; 90 days for automation action log
- Format: structured JSON, one event per line — enables grep-based querying

### 5.3 Database Size Management

- Conversation turns older than 90 days: compressed to summaries and deleted
- Interaction log entries older than 90 days: deleted
- Trigger history: retain only last 30 days
- Maximum database size: 50 MB (soft limit) / 100 MB (hard limit — triggers cleanup)

```swift
func performMaintenanceSweep() async {
    // Run daily at 3 AM
    let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
    await learningSystem.deleteInteractionsOlderThan(cutoff)
    await learningSystem.compressConversationsOlderThan(cutoff)
    await learningSystem.vacuumIfNeeded()  // PRAGMA auto_vacuum = INCREMENTAL
}
```

---

## 6. Network Resource Management

BUTLER makes network calls in one direction only: outbound to `api.anthropic.com`.

### 6.1 Request Characteristics

| Type | Frequency | Payload size | Response size |
|------|-----------|-------------|---------------|
| Claude API (user-initiated) | On demand | 2–8 KB | 0.5–4 KB streamed |
| Claude API (background summarization) | ~once per 20 turns | 4–12 KB | 0.5–1 KB |
| Sparkle update check | Once per 24h | <1 KB | <5 KB |
| ElevenLabs TTS (premium) | Per response | 0.2–1 KB | 50–200 KB audio |

### 6.2 Network Failure Handling

| Failure | Response |
|---------|---------|
| DNS failure | Offline mode: rule-based suggestions only, TTS fallback to native |
| TCP timeout | Retry with exponential backoff (1s, 2s, 4s), max 3 retries |
| HTTP 429 (rate limit) | Backoff per Retry-After header |
| HTTP 5xx | Backoff, max 3 retries, then surface error |
| HTTP 401 | Surface API key error immediately, do not retry |

### 6.3 Bandwidth Efficiency

- Streaming API: responses start rendering in <500ms without waiting for completion
- No telemetry transmitted (opt-in only)
- No crash data transmitted without explicit user consent
- No behavioral data ever transmitted

---

## 7. Battery Impact Management

### 7.1 Activity Profile by Power State

| Power State | Changes |
|------------|---------|
| Plugged in | Full functionality, 60fps animation during active states |
| On battery (default) | 30fps animation, FSEvents poll interval increased to 15s |
| Low Power Mode (macOS) | 15fps animation, idle detection only, no FSEvents, no proactive suggestions |

```swift
// Observe power source and Low Power Mode changes
NotificationCenter.default.addObserver(
    forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
    object: nil, queue: .main
) { _ in
    self.resourceManager.updatePowerState()
}
```

### 7.2 Background Activity Throttling

When BUTLER is not in active interaction:
- Claude API: no background calls (no polling)
- Activity Monitor: event-driven (NSWorkspace observer has no poll cost)
- FSEvents: batched at 5-15s depending on power state
- Idle detection: polled every 10-60s depending on power state
- Visualization Engine: 30fps idle breathing, 1fps if on battery + no user activity for 5min

### 7.3 Thermal Throttling

```swift
// Subscribe to thermal state notifications
ProcessInfo.processInfo.publisher(for: \.thermalState)
    .sink { state in
        switch state {
        case .nominal, .fair:
            break  // No change
        case .serious:
            visualizationEngine.setFrameRate(15)
            activityMonitor.setPollInterval(.slow)
        case .critical:
            visualizationEngine.setFrameRate(1)
            activityMonitor.suspend()
            interventionEngine.suspend()
        @unknown default:
            break
        }
    }
```

---

## 8. Concurrency Model

BUTLER uses Swift concurrency (async/await + actors) throughout.

- All modules are Swift actors — no shared mutable state between modules
- Main thread: UI updates only (`@MainActor` for Visualization Engine)
- Background tasks: structured concurrency (`TaskGroup`, `Task.detached` for truly independent work)
- Combine publishers bridge between modules (backpressure-aware)
- No `DispatchQueue.main.async` patterns (use `@MainActor` instead)

### 8.1 Thread Priority Policy

| Task | Priority |
|------|---------|
| Voice STT real-time processing | `.userInitiated` |
| Claude API streaming | `.userInitiated` |
| UI animation | `.userInteractive` (main thread) |
| Context analysis | `.utility` |
| SQLite writes | `.background` |
| Log writes | `.background` |
| Background summarization | `.background` |
| Maintenance sweeps | `.background` |

---

## 9. Performance Monitoring

### 9.1 Internal Metrics (No Telemetry)

BUTLER tracks these metrics locally for `butler diagnostics` and `butler status`:

```swift
struct PerformanceMetrics {
    var cpuUsage60sAvg: Double
    var ramUsageMB: Int
    var gpuUsagePercent: Double
    var apiCallCount24h: Int
    var apiAverageLatencyMs: Double
    var dbSizeMB: Double
    var suggestionsTriggered7d: Int
    var suggestionsEngaged7d: Int
    var suggestionsDismissed7d: Int
}
```

These are computed on-demand (for `butler status` or `butler diagnostics`) not continuously tracked. No data is transmitted.

### 9.2 Latency Targets

| Operation | Target | Degraded | Hard Limit |
|-----------|--------|---------|-----------|
| STT finalization (speech end → transcript) | <300ms | <500ms | 1000ms |
| Claude first token (transcript → API response start) | <800ms | <1200ms | 2000ms |
| TTS first word (response start → speech begins) | <200ms | <400ms | 600ms |
| Total round trip (speech end → first spoken word) | **<1.5s** | <2.0s | 3.0s |
| Context analyzer evaluation | <50ms | <100ms | 200ms |
| SQLite profile read | <5ms | <20ms | 50ms |
| CLI command response (non-speak) | <200ms | <500ms | 1000ms |
| App cold start to ready | <2s | <3s | 5s |

# PRD-08: BUTLER — 24-Week Engineering Sprint Plan

**Version:** 2.0
**Date:** 2026-03-03
**Status:** Draft — Extended to 24 weeks for CLI, distribution, and edge case hardening
**Owner:** Engineering Lead

---

## 1. Team Assumptions

| Role | Count | Notes |
|------|-------|-------|
| iOS/macOS Engineer (Swift/SwiftUI) | 2 | Primary app development |
| Backend/Integration Engineer | 1 | Claude API, SQLite, data layer |
| Design Engineer / Animator | 1 | Pulse, Glass Chamber, UX |
| Product/QA | 1 | Testing, user research, spec refinement |

*Adjust sprint scope accordingly if team is smaller.*

---

## 2. Sprint Overview

| Sprint | Weeks | Theme | Deliverable |
|--------|-------|-------|-------------|
| 1 | 1–2 | Foundation | App skeleton, window management, Claude API |
| 2 | 3–4 | Voice Core | STT, TTS, push-to-talk |
| 3 | 5–6 | Glass Chamber UI | Full chamber window + conversation panel |
| 4 | 7–8 | Pulse Animation | State machine + animation engine |
| 5 | 9–10 | Personality + Onboarding | Config UI, system prompt, onboarding flow |
| 6 | 11–12 | Activity Monitor + Context | Tier 1/2 signals, context analyzer |
| 7 | 13–14 | Intervention Engine | Decision engine, anti-annoyance, behavioral memory |
| 8 | 15–16 | CLI + IPC Infrastructure | `butler` binary, Unix socket, command handlers |
| 9 | 17–18 | Distribution + Code Signing | DMG, terminal installer, Homebrew, notarization pipeline |
| 10 | 19–20 | Tier 3 Automation | File ops, AppleScript, Shortcuts, calendar |
| 11 | 21–22 | Performance + Resource Management | CPU/RAM targets, thermal, battery, concurrency |
| 12 | 23–24 | Edge Case Hardening + Launch | EC catalog validation, beta, notarized release |

---

## 3. Sprint Details

---

### Sprint 1 (Weeks 1–2): Foundation

**Goal:** Runnable app that can send a message to Claude and display the response.

#### Week 1 Tasks

**Engineering:**
- [ ] Xcode project setup (Swift Package Manager, target configurations)
- [ ] Direct distribution entitlements file (non-sandboxed)
- [ ] App Store entitlements file (sandboxed variant)
- [ ] `NSPanel` subclass: `ButlerPanel` — floating, non-activating
- [ ] Basic window controller: show/hide, position persistence
- [ ] `NSVisualEffectView` blur background — glass material
- [ ] Keychain service for API key storage (read/write/delete)
- [ ] API key entry UI (secure text field, masked display)
- [ ] Basic `ClaudeAPIClient`: synchronous request → response (no streaming yet)

**Design:**
- [ ] Define Glass Chamber dimensions and corner radius
- [ ] Color palette: background blur, glow colors, text colors
- [ ] Typography spec: SF Pro, sizes, weights

#### Week 2 Tasks

**Engineering:**
- [ ] Streaming Claude API client (`AsyncThrowingStream<String, Error>`)
- [ ] System prompt template (hardcoded for now)
- [ ] Basic chat message model (`Message`, `Role`, `ConversationSession`)
- [ ] SQLite database setup (GRDB.swift dependency)
- [ ] Conversation history table schema + basic CRUD
- [ ] Simple text-based chat panel (no voice yet)
- [ ] App lifecycle: launch agent, menu bar item, dock icon hidden

**Testing:**
- [ ] Unit tests: Claude API client (mock responses)
- [ ] Unit tests: Keychain read/write
- [ ] Integration test: send message → streaming response → display

**Sprint 1 Definition of Done:**
- App launches as floating NSPanel
- User can type a message and receive a streaming Claude response
- API key stored securely in Keychain
- Conversation persists to SQLite

---

### Sprint 2 (Weeks 3–4): Voice Core

**Goal:** Full push-to-talk voice input and voice output, synchronized.

#### Week 3 Tasks

**Engineering:**
- [ ] `SpeechInputService` — SFSpeechRecognizer setup
- [ ] Push-to-talk: global hotkey registration (`CGEventTap`)
- [ ] Hold → record, release → finalize transcription
- [ ] Partial results display in conversation panel (real-time)
- [ ] Microphone permission request flow with clear explanation
- [ ] Error handling: no microphone, no speech permission, timeout

#### Week 4 Tasks

**Engineering:**
- [ ] `SpeechOutputService` — AVSpeechSynthesizer
- [ ] 4 voice presets mapped to AVSpeechSynthesisVoice identifiers
- [ ] TTS begins on Claude streaming completion (or sentence-by-sentence)
- [ ] Interrupt TTS on new user input
- [ ] Amplitude extraction from TTS output (AVAudioEngine tap)
- [ ] Amplitude published via Combine publisher (for animation later)
- [ ] Voice speed and pitch controls (wired to personality config)

**Design:**
- [ ] Listening state visual indicator (status bar text)
- [ ] Voice waveform mini-visualization (2D amplitude bar, placeholder)

**Testing:**
- [ ] Voice round-trip test: speak → transcribe → Claude → TTS
- [ ] Measure: speech end to first TTS word latency (target: <1.5s)
- [ ] Test: microphone permission denied — graceful fallback
- [ ] Test: TTS interrupted correctly on new input

**Sprint 2 Definition of Done:**
- Full voice interaction works end-to-end
- Latency <1.5s measured and documented
- All 4 voice presets produce distinct output
- Amplitude signal publishing confirmed

---

### Sprint 3 (Weeks 5–6): Glass Chamber UI

**Goal:** Complete Glass Chamber UI with all states and conversation panel.

#### Week 5 Tasks

**Design + Engineering:**
- [ ] Full Glass Chamber SwiftUI layout spec finalized
- [ ] Idle mode: compact vertical panel, placeholder pulse area
- [ ] Active mode: 10–15% size expansion animation
- [ ] Conversation mode: chat panel slide-in (from right or below)
- [ ] Message bubble components: user (right-align), BUTLER (left-align)
- [ ] Status indicator bar: "Listening…" / "Thinking…" / "Alfred" / "Idle"
- [ ] Timestamp display in conversation

#### Week 6 Tasks

**Engineering:**
- [ ] Quick controls bar: Mic toggle, Mute, Focus Mode, Collapse
- [ ] Collapse to orb: animation (expand → compress → small circle)
- [ ] Mouse proximity detection → auto-expand from orb
- [ ] Auto-hide timer (configurable, default 30s)
- [ ] Drag to reposition (any screen edge)
- [ ] Position persistence across launches (UserDefaults)
- [ ] Multi-Space behavior: `.canJoinAllSpaces`
- [ ] Transparency slider wired to `NSVisualEffectView`

**Design:**
- [ ] Orb design (size: 40pt diameter, glow, pulse)
- [ ] Quick controls icon design
- [ ] Conversation bubble design (dark glass, corner radius, shadow)

**Testing:**
- [ ] Test on multiple screen resolutions (13" MBP, 27" Studio Display)
- [ ] Test window behavior with multiple Spaces
- [ ] Test auto-hide and proximity detection
- [ ] Test chamber position persistence

**Sprint 3 Definition of Done:**
- Glass Chamber renders correctly at all screen sizes
- All modes (idle, active, conversation, orb) transition smoothly
- Window management behavior correct on multiple Spaces

---

### Sprint 4 (Weeks 7–8): Pulse Animation Engine

**Goal:** Full animated pulse with all states, color mapping, and audio reactivity.

#### Week 7 Tasks

**Design + Engineering:**
- [ ] Choose rendering approach: WebGL/Three.js in WKWebView (Phase 1)
- [ ] Define full pulse state machine (8 states)
- [ ] Three.js scene setup: geometry, shader, lighting
- [ ] Idle state: slow breathing oscillation (4s cycle)
- [ ] Listening state: white + ripple expansion
- [ ] Thinking state: blue, expanding waveforms
- [ ] Speaking state: gold, amplitude-driven modulation

**Engineering:**
- [ ] Swift ↔ WKWebView JS bridge (`WKScriptMessageHandler`)
- [ ] State message format: JSON `{state, amplitude, urgency, confidence}`
- [ ] Amplitude data pipe: AVAudioEngine → Combine → WKWebView at 60fps
- [ ] State transition: interpolated (no hard cuts, CSS/GLSL ease)

#### Week 8 Tasks

**Engineering:**
- [ ] Remaining states: Concerned (red, angular), Alert (amber, spike), Success (green bloom), Creative (purple fractal)
- [ ] Chamber glow sync: SwiftUI layer glow matches pulse state color
- [ ] Idle breathing (background thread, minimal CPU)
- [ ] Battery mode: reduce to 30fps when on battery power
- [ ] Reduced motion mode: honor `NSAccessibilityPrefersReducedMotion`

**Design:**
- [ ] Animation spec review — all 8 states sign-off
- [ ] Color palette final values (hex codes for each state)
- [ ] Transition timing curves defined

**Testing:**
- [ ] CPU usage during animation: target <2% idle, <8% during full speaking state
- [ ] All 8 states verified visually on dark and light desktop backgrounds
- [ ] Audio-reactive sync: visually verify pulse tracks voice amplitude
- [ ] Transition smoothness: no frame drops on M1/M2/M3 Mac

**Sprint 4 Definition of Done:**
- All 8 pulse states render correctly
- Audio-reactive speaking state confirmed
- Chamber glow syncs to pulse state
- CPU target met

---

### Sprint 5 (Weeks 9–10): Personality Engine & Onboarding

**Goal:** Full personality configuration and complete onboarding experience.

#### Week 9 Tasks

**Engineering:**
- [ ] `PersonalityConfig` model (Codable, persisted to SQLite)
- [ ] `PersonalityEngine.buildSystemPrompt()` — full template with all variables
- [ ] Settings panel: Personality tab (name, sliders, voice preset)
- [ ] Settings panel: Voice tab (preset, speed, ElevenLabs key)
- [ ] Settings panel: Appearance tab (transparency, size, corner, auto-hide)
- [ ] Settings panel: Privacy tab (export, delete)
- [ ] Hot-reload: personality changes apply to next Claude request

#### Week 10 Tasks

**Engineering + Design:**
- [ ] Onboarding screen 1: Welcome animation (pulse intro)
- [ ] Onboarding screen 2: Name selection
- [ ] Onboarding screen 3: Voice & personality setup with live preview
- [ ] Onboarding screen 4: Permission tier explanation and selection
- [ ] Onboarding screen 5: API key setup and validation
- [ ] Onboarding screen 6: Interactive tutorial (simulated suggestion)
- [ ] Skip tutorial flow
- [ ] Onboarding state persisted — don't re-show on relaunch

**Testing:**
- [ ] All onboarding paths tested (skip, complete, API key invalid)
- [ ] Personality changes reflect immediately in Claude responses
- [ ] Voice preset plays correctly in onboarding preview

**Sprint 5 Definition of Done:**
- Full onboarding flow works end-to-end
- All settings tabs functional
- Personality correctly influences Claude system prompt

---

### Sprint 6 (Weeks 11–12): Activity Monitor & Context Analyzer

**Goal:** BUTLER can observe user activity (Tier 1 and 2) and generate context events.

#### Week 11 Tasks

**Engineering:**
- [ ] `ActivityMonitor` class: `NSWorkspace` active app publisher
- [ ] Browser domain extraction: Safari, Chrome, Firefox, Arc adapters
- [ ] Permission request UI for Accessibility (Tier 1)
- [ ] `DownloadsFolderMonitor`: FSEvents watcher + scan function
- [ ] Idle time detection: IOHIDSystem query
- [ ] Permission dashboard: Permissions tab fully wired
- [ ] Individual permission toggles (each triggers appropriate system permission request)

#### Week 12 Tasks

**Engineering:**
- [ ] `ContextAnalyzer`: rule engine (JSON-configurable)
- [ ] Initial ruleset: downloads clutter, idle detection, app switch frequency
- [ ] `InterventionCandidate` model
- [ ] Suppression checks: video call detection, fullscreen detection
- [ ] Site exclusion list: stored in SQLite, checked before any browser trigger
- [ ] App exclusion list: same pattern
- [ ] Global mute: keyboard shortcut wired, state persisted in session
- [ ] Focus mode: wired to quick controls button

**Testing:**
- [ ] Tier 1: active app correctly detected, browser domain extracted
- [ ] Tier 2: Downloads folder scan returns accurate count
- [ ] Context rules fire correctly on simulated test conditions
- [ ] Video call suppression: Zoom process detected → BUTLER silences
- [ ] Fullscreen detection: BUTLER does not appear over fullscreen app

**Sprint 6 Definition of Done:**
- Activity monitor running correctly at Tier 1 and 2
- Context rules producing InterventionCandidates
- All suppression conditions tested and working

---

### Sprint 7 (Weeks 13–14): Intervention & Behavioral Memory

**Goal:** BUTLER proactively suggests at appropriate moments, learns from responses.

#### Week 13 Tasks

**Engineering:**
- [ ] `InterventionDecisionEngine`: score formula implemented
- [ ] Frequency decay function
- [ ] Time-of-day modifier
- [ ] Threshold enforcement (0.65)
- [ ] Suggestion delivery: Glass Chamber expands, chime, pulse state change
- [ ] Dismissal handling: "Not now", "Never ask", X button
- [ ] Suggestion bubble UI component

#### Week 14 Tasks

**Engineering:**
- [ ] `BehavioralMemoryStore`: full SQLite schema live
- [ ] Tolerance score update logic (engaged/dismissed/ignored/suppressed)
- [ ] Auto-suppress after 3 dismissals (write to `suppressed_triggers`)
- [ ] Trigger history tracking (`trigger_history` table)
- [ ] Behavioral profile summary builder (for Claude system prompt injection)
- [ ] 3 proactive suggestion templates wired end-to-end:
  - Downloads clutter
  - Idle detection
  - App switch frequency
- [ ] Sensitivity slider wired to threshold modifier
- [ ] Quiet Hours: time-based suppression implemented

**Testing:**
- [ ] Score formula: manual calculation matches code output
- [ ] Suggest fires exactly at threshold crossing
- [ ] 3 dismissals → 7-day suppression confirmed
- [ ] Tolerance score updates correctly with each outcome
- [ ] Behavioral summary fed correctly to Claude

**Sprint 7 Definition of Done:**
- End-to-end proactive suggestion working for 3 trigger types
- Reinforcement scoring updating correctly
- Suppression logic working

---

### Sprint 8 (Weeks 15–16): Polish & Launch Preparation

**Goal:** Production-ready build. Smooth, fast, tested, distributable.

#### Week 15 Tasks

**Engineering:**
- [ ] Performance profiling (Instruments): CPU, Memory, GPU
- [ ] Hit all performance targets or document known gaps
- [ ] Crash reporting integration (opt-in, no sensitive data)
- [ ] Sparkle auto-update framework integrated
- [ ] Error states implemented: API error, no microphone, no internet
- [ ] Edge case testing matrix (see below)
- [ ] Database migration system (for future schema changes)
- [ ] Beta build: TestFlight or direct distribution to 20 test users

#### Week 16 Tasks

**Engineering + Product:**
- [ ] Beta feedback triage and critical fixes
- [ ] Accessibility audit: VoiceOver labels, keyboard nav
- [ ] Privacy nutrition label drafted
- [ ] App signing and notarization pipeline set up
- [ ] Sparkle update feed configured
- [ ] macOS version compatibility testing (14, 15)
- [ ] Intel Mac compatibility testing
- [ ] App launch time test: target <2s cold start
- [ ] Final performance benchmark documentation

**Marketing/Product:**
- [ ] Demo video recorded
- [ ] Landing page content final
- [ ] Privacy policy drafted and published
- [ ] Press kit prepared

**Sprint 8 Definition of Done:**
- App notarized and distributable
- Zero known P0/P1 bugs
- All performance targets met
- 20 beta users complete trial without critical issues

---

## 4. Edge Case Test Matrix

| Scenario | Expected Behavior |
|----------|------------------|
| API key invalid on launch | Onboarding prompts re-entry |
| API unreachable (no internet) | Offline mode, rule-based suggestions only |
| Microphone access denied | Voice disabled, chat-only mode |
| Zoom call starts mid-session | BUTLER silences within 2 seconds |
| Screen recording starts | BUTLER silences within 2 seconds |
| Keynote presentation fullscreen | Chamber auto-hides |
| Mac goes to sleep | Monitoring paused, state preserved |
| Mac wakes | Monitoring resumes, idle timer resets |
| External display connected/disconnected | Chamber repositions gracefully |
| User dismisses same suggestion 3 times | 7-day auto-suppress fires |
| Database write fails (disk full) | Graceful warning, feature degrades not crashes |
| Two BUTLER windows (should not happen) | Single instance enforced |
| User deletes all data | Resets to clean state without crash |
| macOS update (minor) | AX adapters tested, auto-update to fix if broken |

---

## 5. Post-Launch Phase 3 Backlog (Weeks 17–24)

| Week | Focus |
|------|-------|
| 17–18 | Tier 3 permission unlock flow + file operations (move, organize, create folder) |
| 19–20 | Shortcuts integration + AppleScript executor |
| 21–22 | Draft email + document summarization |
| 23–24 | Calendar integration + wake word detection |

---

## 6. Key Milestones

| Date | Milestone |
|------|-----------|
| End of Week 2 | Claude API + basic chat working |
| End of Week 4 | Full voice round-trip working, latency measured |
| End of Week 6 | Glass Chamber UI complete, all states |
| End of Week 8 | Pulse animation complete, audio-reactive |
| End of Week 10 | Full onboarding + personality engine |
| End of Week 12 | Activity monitoring live, context engine running |
| End of Week 14 | Proactive suggestions working with behavioral learning |
| End of Week 16 | CLI + IPC complete: `butler status/speak/config` all functional |
| End of Week 18 | Notarized DMG distributable; Homebrew tap live |
| End of Week 20 | Tier 3 automation complete with undo and action log |
| End of Week 22 | All performance targets met and documented |
| End of Week 23 | Beta to 50 users — all 40 EC catalog items passing |
| End of Week 24 | **v1.0 release — notarized, stapled, distributed** |

---

## 6. Sprints 8–12 Detail

---

### Sprint 8 (Weeks 15–16): CLI + IPC Infrastructure

**Goal:** `butler` binary works end-to-end. All core commands functional.

#### Week 15 Tasks

- [ ] Swift Package: `butler-cli` target — thin IPC client binary
- [ ] `ButlerIPCProtocol` library: request/response models, Codable JSON
- [ ] `CLIController` actor in BUTLER.app: Unix socket server
- [ ] Socket creation at `~/.butler/run/butler.sock` (0600)
- [ ] Session token generation + `~/.butler/run/.auth` write (0600)
- [ ] CLI auth: reads token, includes in every request
- [ ] `CommandRouter`: dispatches to handler actors
- [ ] `StatusCommandHandler`: full system status JSON response
- [ ] `ConfigCommandHandler`: list, get, set, reset wired to config store

#### Week 16 Tasks

- [ ] `SpeakCommandHandler`: pipes user text to Claude, streams response back to CLI
- [ ] `LogsCommandHandler`: filtered log streaming
- [ ] `PermissionsCommandHandler`: status, grant (opens System Settings), revoke
- [ ] `DiagnosticsCommandHandler`: full health check output
- [ ] `ResetCommandHandler`: learning, suppression, personality, all
- [ ] Headless mode: `--headless` flag, `NSApp.setActivationPolicy(.prohibited)`
- [ ] CLI auto-launch: detect no socket → launch app → poll → connect
- [ ] Stale socket recovery: ECONNREFUSED → unlink → relaunch
- [ ] Shell completion scripts: zsh `_butler`, bash `butler.bash`, fish `butler.fish`
- [ ] `butler --help` and per-command `--help` output

**Sprint 8 Definition of Done:**
- `butler status` returns full system JSON
- `butler speak "hello"` produces Claude response in terminal and via TTS
- `butler config set personality.name "Sage"` persists correctly
- CLI auto-launches BUTLER.app if not running
- All completion scripts install without errors

---

### Sprint 9 (Weeks 17–18): Distribution + Code Signing

**Goal:** Notarized DMG produced by CI. Homebrew tap live. Terminal installer working.

#### Week 17 Tasks

- [ ] Developer ID Application certificate enrolled and stored
- [ ] Entitlements files: `Butler.entitlements`, `butler-cli.entitlements`
- [ ] Hardened Runtime enabled on all targets
- [ ] `codesign` script: sign frameworks → sign butler-cli → sign app bundle
- [ ] `spctl --assess` verification step in build script
- [ ] `create-dmg` integration: custom background, icon layout
- [ ] DMG codesign step
- [ ] `xcrun notarytool submit` + `xcrun stapler staple` pipeline

#### Week 18 Tasks

- [ ] GitHub Actions workflow: build → sign → notarize → staple → release
- [ ] CI secrets: certificate base64, team ID, Apple ID, app-specific password
- [ ] Sparkle 2 integration: appcast URL, EdDSA key generation
- [ ] Sparkle: in-app update check, Glass Chamber update notification
- [ ] `butler update` CLI command wired to Sparkle
- [ ] Terminal installer bash script (`install.butlerapp.com`)
- [ ] SHA-256 verification in terminal installer
- [ ] Homebrew formula: `butler-app/homebrew-tap` repo created
- [ ] Homebrew cask: `butler` cask submitted to tap
- [ ] LaunchAgent plist: install/uninstall in `butler install/uninstall`
- [ ] `butler uninstall` removes all artifacts

**Sprint 9 Definition of Done:**
- CI produces a notarized, stapled DMG on every version tag push
- Stapler validates: "The validate action worked!"
- `brew install butler-app/tap/butler` installs CLI successfully
- `curl -fsSL https://install.butlerapp.com | bash` installs end-to-end

---

### Sprint 10 (Weeks 19–20): Tier 3 Automation

**Goal:** File operations, AppleScript, Shortcuts, and calendar fully functional with safety controls.

#### Week 19 Tasks

- [ ] `AutomationExecutionLayer` actor: full implementation
- [ ] File ops: move, rename, create folder, trash (no permanent delete)
- [ ] Pre-execution conflict check (naming conflicts at destination)
- [ ] Undo handler: 30-second window, weak reference pattern
- [ ] Action log: SQLite `action_log` table, log before execution
- [ ] User confirmation flow: Glass Chamber confirmation dialog
- [ ] Confirmation UI: show action summary, file count, destination

#### Week 20 Tasks

- [ ] AppleScript executor: timeout (10s), shell command block (regex check)
- [ ] Shortcuts integration: URL scheme trigger, per-shortcut authorization
- [ ] Draft email action: compose via `mailto:` or Mail.app scripting
- [ ] Calendar event creation: EventKit write with user confirmation
- [ ] `butler speak "move files"` → routes to automation via Claude response
- [ ] Tier 3 unlock: 7-day Tier 2 gate enforced at permission dashboard
- [ ] All EC-032 through EC-035 edge cases implemented

**Sprint 10 Definition of Done:**
- Voice command "move all PDFs to Documents" executes with confirmation
- Undo window works at exactly 30 seconds
- AppleScript with `do shell script` is rejected before user sees it
- 7-day Tier 2 gate prevents premature Tier 3 unlock

---

### Sprint 11 (Weeks 21–22): Performance + Resource Management

**Goal:** All resource targets from PRD-17 met and documented. Concurrency model validated.

#### Week 21 Tasks

- [ ] Instruments profiling: CPU, memory, GPU across all module states
- [ ] Idle CPU target: <2% — identify and fix any polling hot paths
- [ ] RAM target: <150MB idle — identify WKWebView memory leaks
- [ ] GPU frame rate adaptation: 60fps → 30fps on battery, 15fps thermal
- [ ] Memory pressure handler: warning and critical levels
- [ ] `NSProcessInfoPowerStateDidChange` observer: Low Power Mode handling
- [ ] Thermal state observer: `ProcessInfo.thermalState` subscription

#### Week 22 Tasks

- [ ] SQLite optimization: WAL mode, synchronous=NORMAL, index review
- [ ] Write batching: behavioral profile updates debounced 500ms
- [ ] Database maintenance sweep: scheduled 3 AM daily via `BGTaskScheduler`
- [ ] Log rotation: 10MB max, 1 prior log retained
- [ ] Network failure handling: all API error codes handled (PRD-17 section 6.2)
- [ ] Latency benchmark: end-to-end voice round trip <1.5s documented
- [ ] `butler diagnostics` performance section: CPU, RAM, latency, DB size
- [ ] Battery impact: macOS Activity Monitor shows "Low" for BUTLER

**Sprint 11 Definition of Done:**
- Instruments trace shows <2% CPU idle for full 5-minute session
- RAM stays <150MB in idle Instruments snapshot
- Voice latency (speech end → first TTS word) measured <1.5s on M2 MacBook
- `butler diagnostics` reports all targets as met

---

### Sprint 12 (Weeks 23–24): Edge Case Hardening + Launch

**Goal:** All EC catalog items pass. 50 beta users complete trial. v1.0 released.

#### Week 23 Tasks

- [ ] EC catalog validation: all 40 edge cases from PRD-19 tested
- [ ] Automated CI tests for: EC-002, EC-006, EC-007, EC-008, EC-011, EC-022, EC-024, EC-031, EC-034, EC-036, EC-037, EC-040
- [ ] Manual test checklist for: EC-017, EC-018, EC-027, EC-028, EC-029, EC-030
- [ ] Beta distribution to 50 users: direct download link (notarized DMG)
- [ ] Beta feedback triage: P0/P1 bugs fixed within this sprint
- [ ] Accessibility audit: VoiceOver, keyboard navigation, reduced motion
- [ ] `butler diagnostics --export` validated: JSON report is complete

#### Week 24 Tasks

- [ ] All P0/P1 bugs resolved
- [ ] Final notarization run: production DMG
- [ ] Sparkle appcast published with production URL
- [ ] `brew install --cask butler` updated to v1.0.0
- [ ] Terminal installer script updated with v1.0.0 SHA-256
- [ ] Landing page live
- [ ] Privacy policy published
- [ ] Press kit distributed to embargo list
- [ ] **Product Hunt launch scheduled**
- [ ] v1.0.0 git tag pushed → CI produces final release DMG

**Sprint 12 Definition of Done:**
- Zero known P0/P1 bugs
- All 40 EC catalog items: pass
- Notarized DMG validates: `spctl --assess` → "accepted"
- 50 beta users: zero reports of BUTLER interrupting during a video call
- **v1.0 released**

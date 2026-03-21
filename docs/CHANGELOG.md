# BUTLER — Changelog

All notable changes, fixes, and new features are documented here.
Format: `[YYYY-MM-DD] Type — Description (commit)`

---

## 2026-03-21

### fix — 8 PRD-20 divergences in birth phase (commit `9e0b85e`)
**Files:** `BirthPhaseViewController.swift`, `BirthOrbView.swift`, `BirthPhaseCoordinator.swift`, `AppDelegate.swift`

Fixed all 8 confirmed divergences from the PRD-20 birth phase specification:

- **BUG-A1** — Orb was visible during dormant (Phase 0). `birthOrbView.isHidden = false` was set on `.dormant` case entry. Fixed: the entire `orbContainerView` is now hidden by default in `buildUI()` and on `.dormant` case entry; `.booting` reveals it.
- **BUG-B1** — `OrbLayerDelegate` used amber/gold colors for all phases. PRD requires cold-blue for phases 0–2 (dormant, booting, digitalAwakening) and gold/amber only on the voiceReceived surge. Fixed: added `coldGlow`/`coldCore`/`coldHot` static helpers and `isWarmPhase` computed var. Phase-aware instance methods `glowColor`/`coreColor`/`hotColor` route to the correct palette. All drawing routines (`drawCore`, `drawArcs`, `drawFlare`, `drawSpark`) updated to use the instance accessors.
- **BUG-D1/M1** — `updatePulseWebView` only mapped to two states (speaking/idle). PRD requires four states. Fixed: new three-parameter `updatePulseWebView(isSpeaking:isListening:isThinking:)` emits `listening(0.5)` during user answer turns and `idle(0.2)` between turns.
- **BUG-D2** — PulseWebView never entered `thinking` state. Fixed by BUG-D1 fix: `isThinking = (coordinator.phase == .discovery && !isSpeaking && !isListening)` covers the 1-second discovery window before BUTLER begins speaking.
- **BUG-F2** — Q1 answer wrote to both `UserDefaults["butler.user.name"]` AND `MemoryWriter(.personal)`. PRD spec only defines the UserDefaults write for Q1. Fixed: removed `MemoryWriter.shared.appendFact("User's name: ...")` from the `"name"` case.
- **BUG-H1** — Window fade animation used `ctx.duration = 0.5`. PRD specifies 0.6s. Fixed in `AppDelegate.handleBirthComplete()`.
- **BUG-L1** — Mic indicator was shown on Phase 5 (questioning) entry before `isListeningForAnswer == true`. `startMicPulse()` forced `micIndicatorView.isHidden = false`. Fixed: `startMicPulse()` no longer sets visibility; it only starts the animation timer. Visibility is exclusively controlled by the 80ms `syncUI` loop via `micIndicatorView.isHidden = !isListening`.

---

### feat — Birth Phase: Pure AppKit NSViewController (commit `6c9878b`)
**Files:** `BirthPhaseViewController.swift` (new), `AppDelegate.swift`

Replaced the SwiftUI `NSHostingView<BirthPhaseView>` with a pure AppKit `BirthPhaseViewController`. Root cause: macOS 26 beta (25C56) has a bug where `swift_task_isCurrentExecutorWithFlagsImpl` dereferences an invalid MainActor isa pointer. SwiftUI's private `AppKitEventBindingBridge` intercepts all `NSGestureRecognizer` actions inside any `NSHostingView`, routing them through this broken executor check. No workaround was possible. The replacement uses:
- `NSVisualEffectView` for glass background
- `BirthOrbNSView` (CALayerDelegate/CVDisplayLink) for phases 0–3
- `WKWebView` for WebGL orb in phases 4–7
- `NSTableView` with pure ObjC `@objc` target/action for voice selection
- `NSTextField` for boot text and subtitles
- 80ms `NSTimer` polling `BirthPhaseCoordinator` state directly (no `@Observable`)

---

### fix — Glass Chamber: transparent canvas background (commit `8269e98`)
**Files:** `Resources/pulse.html`

`pulse.html` had `body { background: #000 }`. The WKWebView had `drawsBackground = false` (transparent) but the HTML document's body was filling itself black. Changed to `background: transparent`. The orb now composites directly on the glass material.

---

### feat — Birth Phase: glass background matching Glass Chamber (commit `2d8842b`)
**Files:** `AppDelegate.swift`, `BirthPhaseView.swift`

- `NSPanel.backgroundColor` changed from `.black` to `.clear`
- `NSHostingView` given `wantsLayer = true` + transparent CALayer background
- `BirthPhaseView` root replaced `Color.black.ignoresSafeArea()` with `RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)` + gradient border stroke — matching `GlassChamberView.glassBackground` exactly

---

### fix — Birth Phase: RunLoop perform to escape AppKitEventBindingBridge (commit `32ba9be`)
**Files:** `AppKitTapOverlay.swift`

Replaced `DispatchQueue.main.async` with `RunLoop.main.perform(#selector:)` in `AppKitTapOverlay` to escape SwiftUI's `AppKitEventBindingBridge.flushActions()` executor check. (Note: this was later superseded by the full AppKit replacement in `6c9878b`.)

---

### fix — BirthOrbView: eliminate EXC_BREAKPOINT/SIGTRAP in Canvas (commit `9372769`)
**Files:** `BirthOrbView.swift`

`Color.resolve(in: EnvironmentValues)` is `@MainActor`-isolated. Inside a SwiftUI `Canvas` draw closure (which runs on a rendering thread, not `@MainActor`), calling it fired `swift_task_isCurrentExecutorWithFlagsImpl` → `SIGTRAP` on every frame. Replaced the SwiftUI `Canvas + TimelineView` with an `NSViewRepresentable` wrapping `BirthOrbNSView` — a pure `CALayerDelegate` + `CVDisplayLink` implementation. No `@MainActor` isolation on the draw callback.

---

### fix — Birth Phase: eliminate EXC_BAD_ACCESS use-after-free crash family (commit `8034fe5`)
**Files:** `VoiceSystem.swift`, `BirthPhaseCoordinator.swift`, `BirthPhaseView.swift`, `VoiceSelectionView.swift`

Six distinct bugs fixed in one sweep:

1. **`finishListening()` double-call**: VAD silence timer and speech recogniser final result both called `finishListening()`. Second call ran `cleanupAudio()` with no tap installed → CoreAudio null pointer. Fixed with `guard isListening else { return }` idempotency guard.

2. **`drainContinuation` double-resume**: `stopSpeaking()` and `StreamingSynthDelegate.onQueueEmpty` could both resume the same continuation. Fixed with atomic nil-before-resume swap at both sites.

3. **`listenContinuation` double-resume**: Same pattern. Fixed identically.

4. **`VoiceSelectionView` preview overlap**: No `.onDisappear` — preview synth kept speaking into voiceReceived phase. Fixed with `.onDisappear { previewSynth.stopSpeaking(at: .immediate) }`.

5. **`BlinkingCursor` Task leak**: `onAppear` Task had no `onDisappear` cancellation. Fixed by storing Task in `@State` and cancelling in `onDisappear`.

6. **`teardownAudio()` only called on skip**: Natural completion path didn't stop `DigitalSoundEngine`. AVAudioEngine kept running during ARC dealloc → real-time audio thread UAF. Fixed by adding `soundEngine.stop()` to end of `runSequence()` and extracting `teardownAudio()` helper called from both `skip()` and natural completion.

---

### fix — AppDelegate: coordinator/window teardown ordering (commit `bdd624b`)
**Files:** `AppDelegate.swift`

`birthPhaseWindow = nil` was running before `birthCoordinator = nil` in `handleBirthComplete()`. This dropped the coordinator's last strong reference while SwiftUI `@Observable` teardown callbacks were still queued → `EXC_BAD_ACCESS` in `objc_msgSend` at nil. Fixed by reordering: nil coordinator first (AppDelegate ref dropped, view still holds it), then nil window (triggers view teardown → coordinator freed cleanly).

---

## Documentation

### docs — PRD-20: Birth Phase specification (2026-03-21)
Created `docs/PRD-20-Birth-Phase.md` — full specification of the birth phase including:
- All 8 phases with dialogue, timing, and visual states
- Voice selection UI and sorting logic
- Audio architecture (DigitalSoundEngine + AVSpeechSynthesizer + VoiceSystem)
- Memory written during onboarding
- Error handling and edge cases
- Implementation file map
- Known platform constraints (macOS 26 beta workarounds)
- Future improvements backlog

Updated `PRD-01-Product-Requirements.md` §4 and `PRD-05-UX-Flows.md` §1 to reflect the actual implemented birth phase (not the original multi-screen wizard concept).

---

## How to Document New Work

When you ship a feature or fix, add an entry here:

```markdown
## YYYY-MM-DD

### [feat|fix|refactor|docs|perf] — Short title (commit `abc1234`)
**Files:** list of changed files

What changed, why it changed, and what problem it solves.
Include root cause for fixes. Include design decisions for features.
```

Types:
- `feat` — new feature or capability
- `fix` — bug fix
- `refactor` — structural improvement, no behavior change
- `perf` — performance improvement
- `docs` — documentation only
- `chore` — build, config, tooling

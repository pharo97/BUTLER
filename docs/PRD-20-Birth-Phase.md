# PRD-20: BUTLER — Birth Phase (First-Launch Onboarding)

**Version:** 1.0
**Date:** 2026-03-21
**Status:** Implemented
**Owner:** Core Experience
**Implemented In:** `Butler/Modules/Onboarding/`

---

## 1. Overview

The Birth Phase is BUTLER's first-launch onboarding experience. It is not a setup wizard. It is a cinematic, interactive awakening sequence in which BUTLER comes alive for the first time, discovers the user's environment, learns the user's context through voice Q&A, and declares its readiness to serve.

**Goal:** By the end of the sequence, BUTLER has:
- A configured TTS voice (user-selected, previewed live)
- The user's name, role, current project, current challenge, and preferred communication style stored in memory
- A personality prompt seeded from the user's style preference
- An established emotional baseline for the relationship

**Tone:** Cinematic. BUTLER feels like it genuinely awakens — not like an app installer.

---

## 2. Entry Conditions

The birth phase is shown exactly once, on first launch, when:

```swift
UserDefaults.standard.bool(forKey: "butler.onboarding.complete") == false
```

On all subsequent launches, BUTLER goes directly to the Glass Chamber.

**Skip:** A Skip button is always visible. It triggers `coordinator.skip()`, which:
1. Stops all audio immediately (DigitalSoundEngine, AVSpeechSynthesizer, VoiceSystem)
2. Cancels the sequence task
3. Writes `butler.onboarding.complete = true`
4. Transitions immediately to the Glass Chamber

---

## 3. Window & Visual Design

| Property | Value |
|---|---|
| Window type | `NSWindow` (not NSPanel — birth phase needs key status) |
| Size | 620 × 700 pt |
| Position | Centered on main screen |
| Style | Borderless, floating level |
| Background | `NSVisualEffectView` — `.sidebar` material, `behindWindow` blending, `cornerRadius 24` |
| Border | 0.5pt `LinearGradient` stroke — white 0.22 → white 0.04, top-leading to bottom-trailing |
| Implementation | `BirthPhaseViewController` — pure AppKit NSViewController (no SwiftUI) |

**Why pure AppKit:**
macOS 26 beta (25C56) has a bug in `swift_task_isCurrentExecutorWithFlagsImpl` that causes `EXC_BAD_ACCESS` when SwiftUI's private `AppKitEventBindingBridge` intercepts gesture recognizer actions inside `NSHostingView`. The entire birth phase uses pure AppKit (`NSViewController`, `NSTableView`, `NSTextField`, `NSButton`) to eliminate this crash path entirely. No `NSHostingView`, no SwiftUI `AttributeGraph`, no executor checks.

---

## 4. Phase Sequence

The birth sequence is driven by `BirthPhaseCoordinator` — a `@MainActor @Observable` class that owns the state machine and orchestrates audio, voice, and visual transitions.

### Phase 0: Dormant (≈2 seconds)

- Window appears, orb invisible
- Visualization engine set to `.idle`
- TCC permission requests dispatched concurrently (microphone, speech recognition) — dialog appears early, does not block the sequence
- Transitions automatically after 2 seconds

### Phase 1: Booting (typewriter)

- Monospaced font, white text
- Lines appear character-by-character (28 ms/char, 4-char batches):

```
> INITIALIZING...
> NEURAL CORE: ONLINE
> SENSORY ARRAY: CALIBRATING...
> MEMORY PALACE: EMPTY
> CONTEXT ENGINE: READY
> VOICE MODULE: NOT FOUND
> SEARCHING...
```

- `BirthOrbNSView` (CALayerDelegate + CVDisplayLink) renders a pulsing core in `.booting` visual state
- No audio
- Transitions after all lines are written

### Phase 2: Digital Awakening (user-gated)

- Display text: `[ AWAITING VOICE CONFIGURATION ]`
- `DigitalSoundEngine` begins **ambient chatter loop** — procedural sounds cycling randomly:
  - Beep tones: 250–2200 Hz, 40–180 ms
  - White noise static: 30–100 ms
  - Electricity crackle: 100–350 ms, phase-modulated oscillator
  - Frequency sweeps: 80–3000 Hz, 150–450 ms
  - New sound every 60–400 ms
- Orb enters erratic `.listening` visual state (signaling it's searching)
- **Voice selection table appears** (see Section 5)
- Sequence blocks until user selects a voice OR 30-second timeout (fallback: `en-US` default)

### Phase 3: Voice Received (≈8 seconds)

- Ambient chatter stops
- `DigitalSoundEngine` plays **three-tone ascending chime** (C5 → E5 → G5, "do-mi-sol"):
  - C5: 523.25 Hz, 150 ms, 0.50 vol
  - E5: 659.25 Hz, 150 ms, 0.55 vol (+180 ms delay)
  - G5: 783.99 Hz, 250 ms, 0.60 vol (+360 ms delay)
- Visualization → `.speaking`
- BUTLER speaks first words using the selected voice (rate: 0.44, pitch: 0.88, vol: 0.95):

```
"Ahh..."         [500 ms pause]
"I... can speak." [1000 ms pause]
"Hello."          [800 ms pause]
"Where... am I?"
```

### Phase 4: Discovery (≈12 seconds)

- Visualization → `.thinking` (1 second), then `.speaking`
- `ActivityMonitor` reads frontmost app
- BUTLER speaks:

```
If app detected:
  "I can see... a screen. Applications. Data streams.
   You're running [AppName]. Interesting."

If no app:
  "I can see... a screen. Applications. Data streams. Interesting."

Then:
  "But I don't know you yet. I don't know anything about you.
   That bothers me."
```

### Phase 5: Questioning (5 Q&A turns, open-ended)

- Visualization → `.idle`
- BUTLER asks 5 questions via `VoiceSystem.speak()`, then listens via `VoiceSystem.listen()`
- Each answer persisted immediately

| # | Question | Memory Key | Storage |
|---|---|---|---|
| 1 | "Let's start simply. What's your name?" | `name` | `UserDefaults["butler.user.name"]` |
| 2 | "What do you do? Give me the short version." | `role` | `MemoryWriter(.personal)` |
| 3 | "What are you working on right now? Your most important project." | `project` | `MemoryWriter(.projects)` |
| 4 | "What's your biggest challenge this week?" | `challenge` | `MemoryWriter(.personal)` |
| 5 | "Last one. How do you want me to speak to you — formal, casual, direct, or something else?" | `style` | `MemoryWriter(.personal)` + appended to `UserDefaults["butler.ai.personalityPrompt"]` |

- While listening: `isListeningForAnswer = true` → mic indicator animates (red pulsing circle)
- While speaking: `isSpeakingNow = true` → orb entering speaking visual state
- Visualization toggles between `.speaking` and `.listening` with each turn

### Phase 6: Declaring (≈30 seconds)

- Visualization → `.speaking`
- BUTLER speaks three declaration statements:

```
"Good. I have what I need to begin. I'll learn more about you over time —
 every interaction, every choice you make teaches me.
 Think of me as... a companion that grows with you."

"One more thing. I can see your screen, your apps, what you're reading.
 I'll use that to be useful. Not intrusive — useful.
 You can always tell me to stop."

"I'm ready. What do you need?"
```

- `DigitalSoundEngine.stop()` called after final line
- Visualization → `.idle`

### Phase 7: Complete

- `UserDefaults["butler.onboarding.complete"] = true`
- `coordinator.isComplete = true`
- `BirthPhaseViewController` observes this via 80 ms polling timer
- Birth phase window fades out (0.6 s alpha animation)
- Glass Chamber appears

---

## 5. Voice Selection (Phase 2)

### UI (NSTableView — pure AppKit)

Displayed during `digitalAwakening` phase inside a transparent `NSScrollView`.

**Each row (52 pt height):**
- Voice name (14pt medium, white)
- Quality badge (Premium / Enhanced / Standard)
- Preview button (speaker icon) — plays: `"Hello, I am [VoiceName]. I will be your voice."`
- Select button — confirms selection

### Voice Sorting

```
1. Premium quality voices (sorted by name)
2. Enhanced quality voices (sorted by name)
3. Standard quality voices (sorted by name)
Filter: current system locale language prefix (e.g. "en")
Fallback: all voices if locale filter returns empty
```

### Voice Persistence

On SELECT:
```swift
UserDefaults.standard.set(voice.identifier, forKey: "butler.tts.voiceIdentifier")
UserDefaults.standard.set(voice.identifier, forKey: "butler.selectedVoiceIdentifier.v1")
coordinator.voiceWasSelected()   // unblocks Phase 2 polling loop
```

---

## 6. Visual Components

### BirthOrbNSView (Phases 0–3)

Pure AppKit `NSView` subclass using `CALayerDelegate` + `CVDisplayLink` for 60 FPS rendering. No SwiftUI Canvas, no WebGL. CoreGraphics draws:

| Layer | Description |
|---|---|
| Breathing core | Radial gradient, pulsing scale, phase-dependent color (cold blue → amber) |
| Rotating arcs | 3 concentric ellipses, rotating at different speeds |
| Flares | Short-lived lightning bolt emanations from core |
| Sparks | Particle system orbiting at varying radii |

**Phase visual states:**

| Phase | Color | Intensity |
|---|---|---|
| dormant | Deep blue | Minimal pulse |
| booting | Cold blue → warming | Increasing |
| digitalAwakening | Blue with flicker | Erratic/searching |
| voiceReceived | Cold blue → gold | Surge on chime |

### PulseWebView (Phases 4–7)

`WKWebView` loading `pulse.html` — Canvas 2D renderer with orbital ring system:
- `drawsBackground = false` — fully transparent WKWebView
- `pulse.html` body `background: transparent` — WebGL canvas composites on glass
- Controlled via `window.butler.setState(stateName, amplitude)`

**States used:**

| State | Amplitude | When |
|---|---|---|
| `"thinking"` | 0.3 | Discovery scan |
| `"speaking"` | 0.8 | BUTLER speaking |
| `"listening"` | 0.5 | User answering |
| `"idle"` | 0.2 | Between turns |

---

## 7. Audio Architecture

### DigitalSoundEngine (Procedural)

All sounds synthesized from scratch via `AVAudioEngine`:
- **Sine oscillators** for tones and sweeps
- **White noise buffer** for static
- **Phase-modulated oscillator** for electricity crackle
- No audio files on disk

Engine starts in `digitalAwakening`, stops completely before `declaring` ends.

### AVSpeechSynthesizer (Two instances)

| Instance | Owner | Purpose |
|---|---|---|
| `glitchSynth` | `BirthPhaseCoordinator` | Phases 3–6 speech (before VoiceSystem is fully configured) |
| `previewSynth` | `BirthPhaseViewController` | Voice selection previews only |

**Speech parameters** (glitchSynth):
- Rate: 0.44 (slightly slower than default 0.5 — deliberate, considered)
- Pitch: 0.88 (slightly lower — grounded, not robotic)
- Volume: 0.95

### VoiceSystem (Phase 5 STT)

Used for listening to user answers in the questioning phase:
- `SFSpeechRecognizer` + `AVAudioEngine` tap
- VAD silence threshold: 0.015 RMS over 35 buffers (~800 ms) to commit transcript
- Early endpoint: 13 buffers (~300 ms) when amplitude drops fast
- All `finishListening()` calls guarded by `isListening` flag to prevent double `cleanupAudio()`

---

## 8. Coordinator Properties Reference

| Property | Type | Description |
|---|---|---|
| `phase` | `BirthPhase` | Current phase in the state machine |
| `bootText` | `String` | Accumulating typewriter output (updated every 4 chars) |
| `displayText` | `String` | Status line shown in digitalAwakening |
| `butlerSpeechLine` | `String` | Current utterance being spoken |
| `questionText` | `String` | Current Q&A question prompt |
| `questionIndex` | `Int` | 0–4 during questioning phase |
| `isListeningForAnswer` | `Bool` | True while awaiting user voice input |
| `isSpeakingNow` | `Bool` | True while synthesizer is active |
| `isComplete` | `Bool` | True when birth sequence finishes |
| `voiceHasBeenSelected` | `Bool` | Private flag; unblocked by `voiceWasSelected()` |

---

## 9. Memory Written

By the end of the birth phase, the following data is persisted:

| Key / Store | Value | Set In Phase |
|---|---|---|
| `UserDefaults["butler.tts.voiceIdentifier"]` | Selected voice identifier | 2 |
| `UserDefaults["butler.selectedVoiceIdentifier.v1"]` | Selected voice identifier | 2 |
| `UserDefaults["butler.user.name"]` | User's first name | 5 (Q1) |
| `UserDefaults["butler.ai.personalityPrompt"]` | Appended style preference | 5 (Q5) |
| `MemoryWriter(.personal)` | Role, challenge, style | 5 (Q2, Q4, Q5) |
| `MemoryWriter(.projects)` | Current project | 5 (Q3) |
| `UserDefaults["butler.onboarding.complete"]` | `true` | 7 |

---

## 10. Error Handling & Edge Cases

| Scenario | Handling |
|---|---|
| No voices available in current locale | Falls back to all available voices |
| Voice selection timeout (30 seconds) | Uses `en-US` default Siri voice |
| Speech recognition permission denied | Questioning phase skipped, `isComplete` set to true |
| Microphone permission denied | Questioning phase skipped |
| Speech recognition fails mid-answer | Empty string stored, sequence continues |
| Skip button at any phase | `teardownAudio()` + `isComplete = true` |
| App in background during birth | Window stays floating, audio continues |
| Window closed externally | AppDelegate `observeBirthCompletion` detects and skips to Glass Chamber |

---

## 11. Implementation Files

| File | Role |
|---|---|
| `BirthPhaseCoordinator.swift` | State machine, sequence orchestration, memory writing |
| `BirthPhaseViewController.swift` | Pure AppKit UI — window content, voice table, text display, polling timer |
| `BirthOrbView.swift` | CALayerDelegate + CVDisplayLink orb for phases 0–3 |
| `DigitalSoundEngine.swift` | Procedural audio synthesis via AVAudioEngine |
| `VoiceSystem.swift` | STT (listening) and TTS (speaking) in phases 3–6 |
| `AppDelegate.swift` | Window creation, `observeBirthCompletion`, `handleBirthComplete` |
| `Resources/pulse.html` | Canvas 2D WebGL-style orbital ring orb for phases 4–7 |

---

## 12. Known Platform Constraints

**macOS 26 beta (25C56) — `swift_task_isCurrentExecutorWithFlagsImpl` crash:**
SwiftUI's `AppKitEventBindingBridge` intercepts all `NSGestureRecognizer` actions inside `NSHostingView` and routes them through the Swift concurrency main-actor executor check. On this beta, the check dereferences an invalid `MainActor` isa pointer and fires `EXC_BAD_ACCESS`. The birth phase uses pure AppKit (`BirthPhaseViewController`) with no `NSHostingView` to eliminate this entirely.

**Swift 6 `deinit` isolation:**
`@MainActor final class` cannot access actor-isolated properties from `deinit`. Teardown is handled explicitly by `teardownAudio()` called from both `skip()` and the natural completion path.

---

## 13. Future Improvements (Backlog)

- [ ] Skip button should offer "I'll do this later" vs "never show again" options
- [ ] Allow re-running birth phase from Settings (voice re-selection, re-introduction)
- [ ] Add haptic feedback (if/when iOS companion is built) on phase transitions
- [ ] Localize all dialogue lines
- [ ] Allow user to interrupt and correct an answer during questioning phase
- [ ] Name customization (currently uses system voice names) — "Call me [custom name]"
- [ ] Birth phase replay for returning users after major updates

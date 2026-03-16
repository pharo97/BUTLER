# BUTLER — Direction Notes
*Source: Boss strategic brief*
*Filed: 2026-03-09*

---

## Vision
BUTLER is not a command-response system like Siri.
It is a **state-aware operating companion** — it knows what you're doing
and acts without being asked.

> "If you're working on a Keynote presentation and your battery hits 10%,
> BUTLER doesn't just give a low-battery warning — it automatically dims
> the screen, saves a backup to iCloud, and asks if you'd like it to find
> the nearest coffee shop with an outlet."

---

## Core Architecture Pillars

### 1. Apple Silicon Optimization (Privacy + Speed)
- **Local LLM via MLX / Llama.cpp** — run reasoning on the Neural Engine, nothing leaves the Mac
- **Core ML** for on-device inference (no cloud, no latency, no privacy risk)
- **Unified Memory** — fast context switching between image analysis, mail drafting, etc.

### 2. The Nervous System — macOS Accessibility Hooks
- **ScreenCaptureKit** — BUTLER *sees* what the user sees:
  - Excel cells, Xcode line numbers, browser content
  - Currently: we use Accessibility API + AppleScript (good MVP)
  - Next: SCK for pixel-perfect screen reading
- **AppleScript + Shortcuts** — voice → action pipelines
  - "Butler, prep the morning briefing" → open Calendar + Safari + Notes

### 3. The Library — Semantic File Indexing
- **Vector embeddings** of every PDF, email, chat log on the Mac
- **Contextual retrieval**: "How much did we spend on cloud hosting last spring?" → finds the relevant invoice lines across 3 files
- **SQLite + vector DB** (e.g. SQLite-VSS or Chroma embedded)
- Standard Spotlight is too literal — we need semantic search

### 4. The Interface — Minimalist HUD
- ✅ Done: Floating Glass Chamber (NSPanel, non-activating)
- ✅ Done: Pulse orb (abstract, animated)
- **System Media Transport** — BUTLER "whispers" over music, then ducks volume back
- Menu bar icon pulsing when listening
- Non-intrusive overlays over current work (SwiftUI overlay on top of any app)

---

## The BUTLER Tech Stack (Boss's Reference)

| Component     | macOS Tech              | Role                                        |
|---------------|-------------------------|---------------------------------------------|
| Speech-to-Text | SFSpeechRecognizer     | ✅ Done — converting voice to tokens        |
| Vision        | Vision Framework / SCK  | OCR + screen reading → next priority        |
| Logic         | Claude API → MLX local  | ✅ Claude streaming done; local LLM = Phase 4 |
| Automation    | Shortcuts / AppIntents  | Controlling other apps — Phase 3            |
| Memory        | SQLite + Vector DB      | ✅ SQLite in plan; vector search = Phase 4  |

---

## Priority Roadmap Derived From Brief

### Immediate (Phase 2B — now building)
- [x] Perception layer (browser URL, selected text, clipboard, calendar)
- [ ] **Streaming TTS pipeline** — speak sentence 1 while generating sentences 2-3
- [ ] Smarter VAD (voice activity detection) — don't wait for fixed timeout

### Near-term (Phase 3)
- [ ] ScreenCaptureKit — see actual screen content (not just app name)
- [ ] AppIntents / AppleScript automation — "open my morning briefing"
- [ ] System audio ducking (lower music volume when BUTLER speaks)
- [ ] Menu bar icon with pulse animation

### Long-term (Phase 4)
- [ ] Local LLM via MLX (Llama 3, Phi-3, Qwen) — full offline + privacy mode
- [ ] Local Whisper STT (faster, offline, no Apple STT limits)
- [ ] Vector search / semantic file indexing (SQLite-VSS)
- [ ] ElevenLabs voice synthesis (higher quality TTS)

---

## Why BUTLER Beats Siri

| Siri                     | BUTLER                                          |
|--------------------------|-------------------------------------------------|
| Command-Response         | State-Aware                                     |
| Reacts only when asked   | Proactively intervenes at the right moment      |
| No context of your work  | Knows your current app, URL, selection, calendar|
| Cloud-only               | Local-first (Phase 4: fully on-device)          |
| Fixed personality        | Learns + evolves from your interaction patterns |

---

## Key Quote to Remember
> "A butler knows where everything is hidden. Standard Spotlight search is
> too literal; BUTLER needs Vector Search."

# PRD-01: BUTLER — Full Product Requirements Document

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Product

---

## 1. Product Overview

### 1.1 Product Name
BUTLER

### 1.2 Tagline
*Your intelligent digital companion. Always present. Never intrusive.*

### 1.3 Product Vision
BUTLER is a desktop-first AI operating companion for macOS that lives inside the operating system as an interactive, voice-enabled, semi-autonomous assistant. It manifests as an animated abstract pulse figure housed in a dedicated Glass Chamber UI, observes user activity with explicit permission, makes contextual suggestions, and can take actions on the system with user authorization.

BUTLER is not a chatbot. It is a presence layer — an ambient operating intelligence that feels like a calm, highly capable executive assistant standing behind you.

### 1.4 Design Philosophy
- **Luxury, not toy.** Every interaction should feel intentional and refined.
- **Assistance, not surveillance.** Consent is foundational, not an afterthought.
- **Restraint, not noise.** Fewer, better suggestions outperform constant chatter.
- **Alive, not uncanny.** Abstract animation creates personality without triggering unease.

---

## 2. Target Users

### 2.1 Primary User Persona — "The Power Professional"
- Age: 28–50
- Role: Founder, product manager, senior engineer, creative director, executive
- Device: MacBook Pro or Mac Studio (macOS 14+)
- Behavior: Heavy multitasker, manages many files and apps simultaneously, has high expectations for tools
- Pain points: Context switching, file clutter, missed focus windows, repetitive tasks
- Motivation: Feels productive and in control; wants intelligent help, not more notifications

### 2.2 Secondary Persona — "The Creative Solo"
- Freelancer, designer, or writer working independently
- Values aesthetic quality in tools
- Appreciates ambient productivity assistance without rigid structure

### 2.3 Non-Target Users
- Casual users with light computing needs
- Users uncomfortable with AI system access
- Enterprise IT-controlled environments (initially)

---

## 3. Core Features

### 3.1 Glass Chamber UI

The primary interface through which users interact with BUTLER.

**Behavior:**
- Semi-transparent glass morphism window (NSVisualEffectView / native blur)
- Always accessible, floating above other apps
- Draggable, pinnable, auto-hideable
- Collapsible to compact corner orb
- Does not cover fullscreen applications, presentations, or screen recordings

**Modes:**
| Mode | Description |
|------|-------------|
| Idle | Small vertical glass panel, pulse floating inside at low intensity |
| Active | Slight expansion when BUTLER speaks or is engaged |
| Conversation | Chat panel slides open beside pulse |
| Settings | Full expansion with configuration tabs |

**Window Controls:**
- Drag chamber anywhere on screen
- Pin to top (always-on-top layer)
- Auto-hide when inactive (configurable timeout)
- Adjustable transparency (0–100%)
- Minimize to corner orb

**Prohibited Behavior:**
- Never appear over fullscreen apps
- Never appear during screen recording or presentations
- Never interrupt active Zoom or video conferencing sessions
- Detect gaming mode (fullscreen + high GPU usage) and suppress

---

### 3.2 Digital Presence Engine (Pulse Figure)

BUTLER's visual representation is an abstract animated waveform figure — not humanoid, not cartoonish. It reflects internal state through shape, color, and motion.

#### 3.2.1 State Machine

```
Idle → Listening → Thinking → Speaking → Concerned → Alert → Success → Creative
```

State transitions are animated (no hard cuts). Each state has defined pulse behavior, color, and chamber glow.

#### 3.2.2 Visual State Specification

| State | Pulse Shape | Color | Chamber Glow | Animation |
|-------|------------|-------|--------------|-----------|
| Idle | Compact orb, slow breathe | Soft white | None | Gentle oscillation |
| Listening | Expanding ripple | White | Faint ripple | Vibration on edges |
| Thinking | Expanding wave | Blue | Intensifies | Waveforms expand |
| Speaking | Modulated wave | Gold | Synchronized | Synced to TTS amplitude |
| Concerned | Angular distortion | Red | Red edge glow | Sharp deformation |
| Alert | Sharp spike | Amber | Amber pulse | Quick spike-settle |
| Success | Fractal bloom | Green | Green flare | Quick expand + settle |
| Creative | Fractal oscillation | Purple | Fractal ripple | Slow rhythmic bloom |

#### 3.2.3 Animation Rules
- Voice amplitude (TTS output) directly drives waveform intensity
- Animation speed reflects urgency of context
- Smoothness reflects confidence level
- Transitions between states must be interpolated (no abrupt changes)
- Idle breathing cycle: ~4 seconds per breath

#### 3.2.4 Visual Evolution (Learning Reflection)
As BUTLER accumulates interaction history:
- Pulse complexity increases subtly over time
- Animation becomes slightly more fluid and confident
- Response cadence reflects learned user pace
- Users can reset visual growth to default state

#### 3.2.5 Rendering Options (Priority Order)
1. Metal shaders (native, highest performance, best battery)
2. WebGL via WKWebView (cross-platform, easier iteration)
3. Lottie with dynamic parameter injection (fallback, limited reactivity)

---

### 3.3 Voice System

#### 3.3.1 Input (STT)
- **Primary:** Apple Speech framework (on-device, private, low latency)
- **Secondary:** OpenAI Whisper local model (optional, for higher accuracy)
- **Modes:**
  - Push-to-talk (hold key or button)
  - Wake word detection (opt-in, "Hey Butler" or custom)
  - Continuous listening (opt-in, highest permission tier)

#### 3.3.2 Output (TTS)
- macOS native voices (NSSpeechSynthesizer / AVSpeechSynthesizer)
- ElevenLabs integration for premium voice packs (requires API key)
- Speed control (0.75x – 1.5x)
- Tone modulation per personality preset

#### 3.3.3 Voice Personality Presets
| Preset | Character |
|--------|-----------|
| Formal British | Measured, precise, dry wit |
| Calm American | Warm, clear, neutral |
| Direct Tactical | Fast, minimal, efficient |
| Warm Mentor | Encouraging, patient, kind |
| Custom | User-defined prompt injection |

#### 3.3.4 Audio-Reactive Pipeline
```
TTS Output → Amplitude Analyzer → Animation Engine → Pulse Modulation
```
Real-time amplitude sampling at ≥60fps drives waveform deformation.

---

### 3.4 Context Awareness Layer

Requires explicit, granular user permission. See Permission Tier Architecture (Section 5).

#### 3.4.1 Observable Signals (by tier)

**Tier 1 — App-Level:**
- Active application name
- Browser domain (not URL path, not page content)
- Time spent in app/domain

**Tier 2 — Context:**
- Downloads folder file count and metadata
- Duplicate file detection
- File system activity (metadata only, no content)
- Calendar event presence (not content)
- Idle time detection
- Browser tab count

**Tier 3 — Automation:**
- File operations (move, rename, organize)
- App control (open, close, focus)
- Browser interaction (with explicit session permission)
- Calendar modification
- Script execution

#### 3.4.2 Context Trigger Examples
| Signal | Condition | Suggestion |
|--------|-----------|------------|
| Downloads folder | >100 files, oldest >7 days | "Your Downloads has 147 files. Shall I sort them?" |
| Amazon open | >45s + >5 product pages | "Comparing prices, or hunting for something specific?" |
| Idle detection | >20min, no input | "You've been idle 20 minutes. Shall I start focus mode?" |
| Late night | After 1 AM + activity | "It's past 1 AM. Should I dim distractions?" |
| Task switching | >3 app switches in 10min | "You've switched apps 5 times. Focus mode?" |
| Calendar gap | >2hr unscheduled window | "You have a 3-hour open block at 2 PM. Schedule it?" |

---

### 3.5 Suggestion & Intervention Engine

#### 3.5.1 Intervention Score Formula
```
Intervention Score = (Context Weight × User Tolerance × Time Modifier × Frequency Decay)
```

**Variables:**
- **Context Weight** (0.0–1.0): Relevance and urgency of trigger (defined per rule)
- **User Tolerance** (0–100): Learned from engagement/dismiss history
- **Time Modifier** (0.5–1.0): Reduced during known focus hours, late night, meetings
- **Frequency Decay** (0.1–1.0): Exponentially decays per trigger type after recent trigger

**Threshold:** Score must exceed 0.65 to trigger intervention.

#### 3.5.2 Anti-Annoyance Logic
- Same trigger type cannot fire within a cooldown window (default: 4 hours)
- 3 consecutive dismissals of same trigger type → auto-suppress for 7 days
- User explicit "don't ask about this" → permanent rule suppression
- Global dismiss during a session → silence all non-critical suggestions for remainder of session
- Frequency cap: maximum 3 proactive suggestions per hour

#### 3.5.3 Suggestion Format
Every suggestion must:
- Be ≤2 sentences
- Be phrased as a question or offer, not a directive
- Include one-tap dismiss option
- Include "never ask about this" option
- Never interrupt fullscreen, video calls, or presentations

---

### 3.6 Personality Engine

#### 3.6.1 Configurable Dimensions
| Parameter | Range | Effect |
|-----------|-------|--------|
| Name | Free text | BUTLER's self-reference and prompt identity |
| Formality | 1–5 | Language register (casual to formal) |
| Proactivity | 1–5 | Suggestion frequency multiplier |
| Humor | 1–5 | Wit injection in responses |
| Directness | 1–5 | Response verbosity (brief to elaborate) |

#### 3.6.2 System Prompt Template
```
You are {name}, a refined digital assistant serving a professional user.
You speak in a {tone} register. You are {directness_descriptor}, {humor_descriptor},
and {formality_descriptor}. You never speak for more than 2 sentences unprompted.
You are proactive at level {proactivity}/5. You prioritize the user's focus above all else.
```

#### 3.6.3 Behavioral Memory Feed
Claude receives a summarized behavioral profile with each prompt:
```json
{
  "user_tolerance": 72,
  "current_focus_state": "productive",
  "recent_dismissals": ["downloads", "idle"],
  "preferred_voice": "formal_british",
  "time_of_day": "afternoon",
  "active_app": "Xcode"
}
```

---

### 3.7 Command Execution Layer

All actions require prior authorization. First-time actions always require confirmation.

#### 3.7.1 Supported Actions (Phase 3+)
| Category | Actions |
|----------|---------|
| File System | Move files, rename files, create folders, delete to trash (not permanent delete) |
| Applications | Open app, close app, bring to focus |
| Documents | Summarize document, draft email, create note |
| Automation | Trigger Shortcuts, run AppleScript, execute script (sandboxed) |
| Calendar | Read events, suggest schedule, create event (with confirmation) |

#### 3.7.2 Execution Safety
- Every action is logged locally
- Reversible actions (move, rename) have 30-second undo window
- Permanent deletions are not supported (trash only)
- Bulk operations require explicit count confirmation
- BUTLER states the action aloud before executing

---

## 3.8 Command Line Interface (CLI)

> Full specification: PRD-11 (CLI Specification) | PRD-12 (CLI Module Architecture)

The `butler` CLI is a first-class interface. All product functionality is accessible without launching the GUI.

**Installation paths:**
- Automatically offered on first GUI launch (creates symlink to `/usr/local/bin/butler`)
- Via terminal installer: `curl -fsSL https://install.butlerapp.com | bash`
- Via Homebrew: `brew install butler-app/tap/butler` (CLI only) or `brew install --cask butler` (full app)

**Command groups:**

| Group | Purpose | Example |
|-------|---------|---------|
| `butler install / update / uninstall` | System lifecycle | `butler install` |
| `butler config set/get/list/reset` | Configuration | `butler config set personality.name "Sage"` |
| `butler speak "<text>"` | Send NL command | `butler speak "Organize Downloads"` |
| `butler status` | Runtime status | `butler status --watch` |
| `butler permissions status/grant/revoke` | Permission management | `butler permissions grant calendar` |
| `butler history list/show/clear` | Interaction history | `butler history list --limit 10` |
| `butler trigger <type>` | Manual trigger (dev/test) | `butler trigger downloads-clutter` |
| `butler logs` | Structured log access | `butler logs --module InterventionEngine --follow` |
| `butler reset <subsystem>` | Reset subsystems | `butler reset learning` |
| `butler diagnostics` | System health check | `butler diagnostics --export ~/report.json` |

**IPC architecture:** The `butler` CLI binary communicates with the running BUTLER.app via a Unix domain socket at `~/.butler/run/butler.sock`. If BUTLER.app is not running, the CLI launches it in headless mode before connecting.

**Scriptability:** All commands support `--json` for machine-readable output and `--force` for non-interactive use.

---

## 3.9 Distribution Methods

> Full specification: PRD-13 (Installation & Distribution) | PRD-14 (Code Signing & Notarization)

BUTLER is distributed outside the Mac App Store. Three installation methods are supported:

| Method | Target | GUI | CLI | Updates |
|--------|--------|-----|-----|---------|
| DMG drag-and-drop | General users | Yes | Post-install prompt | Sparkle in-app |
| Terminal installer | Developers | Yes | Yes | `butler update` |
| Homebrew Cask | Power users | Yes | Yes | `brew upgrade --cask butler` |
| Homebrew CLI only | Terminal users | No | Yes | `brew upgrade butler` |

All distributed binaries are:
- Signed with Developer ID Application certificate
- Notarized by Apple (no Gatekeeper warnings)
- Stapled (notarization ticket embedded — works offline)

---

## 4. User Onboarding Flow

### 4.1 First Launch Sequence
```
1. Welcome screen — product introduction (30 seconds)
2. Name your BUTLER
3. Select voice personality
4. Permission tier selection (see Section 5)
5. Quick voice calibration
6. Tutorial scenario (simulated suggestion + response)
7. Main experience begins
```

### 4.2 Trust Building Principle
- BUTLER starts at Tier 0 (passive) by default
- Tiers are unlocked one at a time, with clear explanation of what each enables
- Permission dashboard is always accessible from Settings
- Every permission can be revoked at any time

---

## 5. Permission Tier Architecture

| Tier | Name | Access | User Grant Required |
|------|------|--------|---------------------|
| 0 | Passive | None. Responds only when invoked. | Default |
| 1 | App-Level | Active app name, browser domain | One-time opt-in |
| 2 | Context | File metadata, duplicate detection, idle detection, calendar presence | Per-category opt-in |
| 3 | Automation | File operations, app control, script execution, calendar modification | Per-action opt-in |

**Rules:**
- Permissions are granted per category, not as a bundle
- Users can revoke any permission at any time from the Permission Dashboard
- No permission persists without explicit re-confirmation after 90 days
- Permission state is displayed in the Glass Chamber status at all times

---

## 6. Safety & Control

### 6.1 Always-Available Controls
- **Global Mute:** Silences all voice and suggestions instantly (keyboard shortcut)
- **Focus Mode:** Suppresses all proactive suggestions
- **Quiet Hours:** Time-based suppression window (e.g., 10 PM – 8 AM)
- **Site Exclusion List:** Domains where BUTLER never triggers
- **App Exclusion List:** Applications where BUTLER never triggers
- **Sensitivity Slider:** Global intervention threshold adjustment

### 6.2 Automatic Suppression (Detection Required)
BUTLER detects and automatically suppresses during:
- Active Zoom, Teams, Google Meet, or other video conferencing
- Screen sharing (any app)
- Fullscreen mode (excluding fullscreen terminals if user is active)
- Presentations (Keynote, PowerPoint, browser fullscreen)
- Gaming (fullscreen + high GPU/CPU usage heuristic)

---

## 7. Data & Privacy Principles

- All behavioral data stored locally (never transmitted)
- Claude API receives only: summarized context, user message, system prompt
- No raw screen content, file contents, or personal data sent to API
- Claude API key is user-provided (bring-your-own-key model in Phase 1)
- All local storage encrypted at rest (AES-256)
- Users can export or delete all stored data at any time
- BUTLER never reads file contents without explicit per-file confirmation

---

## 8. Monetization

### 8.1 Tier 1 — BYOK (Bring Your Own Key)
- User provides Claude API key
- Software subscription: $12/month or $99/year
- All core features included

### 8.2 Tier 2 — Integrated Billing
- BUTLER provides API access (bundled)
- Subscription: $30–40/month
- Includes usage quota; overage billed separately

### 8.3 Premium Add-Ons
| Feature | Price |
|---------|-------|
| Premium voice packs (ElevenLabs) | $5/month or $40/year |
| Custom animated pulse skins | $10 one-time each |
| Advanced automation templates | Included in $30+ tier |
| Persistent memory expansion | Included in $30+ tier |

---

## 9. Platform Scope

### Phase 1–3: macOS
- Minimum: macOS 14 (Sonoma)
- Recommended: macOS 15+
- Architecture: Apple Silicon primary, Intel supported

### Phase 4: iOS Companion
- Notification sync with Mac
- Voice-only interaction mode
- Continuity handoff (begin on Mac, continue on iPhone)
- No independent automation on iOS (mirrors Mac state)

---

## 10. Success Metrics

| Metric | Target (Month 6) |
|--------|-----------------|
| Daily Active Users | >40% of installs |
| Suggestion Engagement Rate | >25% |
| Suggestion Dismiss Rate | <50% |
| Churn Rate (Monthly) | <8% |
| Avg. Session Length | >12 minutes |
| Permission Tier 2+ Adoption | >60% of DAU |
| NPS | >50 |

---

## 11. Out of Scope (V1)

- Windows or Linux support
- Mobile-first features
- Multi-user or team features
- Browser extension
- Cloud storage of behavioral data
- Real-time collaboration features
- Enterprise MDM support
- Third-party plugin API (planned for V2)

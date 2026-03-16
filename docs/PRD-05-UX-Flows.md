# PRD-05: BUTLER — UX Flow Diagrams

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Design / Product

---

## 1. First Launch & Onboarding Flow

```
┌─────────────────────────────────────────────────────┐
│                    APP LAUNCH                       │
└──────────────────────────┬──────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│           WELCOME SCREEN (30 seconds)               │
│   "Meet BUTLER — your digital operating companion"  │
│   [Animated pulse intro — idle → thinking → gold]  │
│                                                     │
│              [Get Started]                          │
└──────────────────────────┬──────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│                 NAME YOUR BUTLER                    │
│                                                     │
│   "What shall I be called?"                        │
│   [ Alfred          ▼ ] or [ type custom name ]    │
│   Suggestions: Alfred / ARIA / MAX / SAGE / NOVA   │
│                                                     │
│                    [Continue]                       │
└──────────────────────────┬──────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│              VOICE & PERSONALITY SETUP              │
│                                                     │
│   "How should I sound?"                            │
│   ○ Formal British   ○ Calm American               │
│   ○ Direct Tactical  ○ Warm Mentor                 │
│   ○ Custom                                         │
│                                                     │
│   [Play Sample]                                    │
│                                                     │
│   Personality sliders:                             │
│   Formality    [─────────────●──────]  4/5         │
│   Proactivity  [──────●─────────────]  3/5         │
│   Humor        [──●─────────────────]  2/5         │
│   Directness   [───────────●────────]  4/5         │
│                                                     │
│                    [Continue]                       │
└──────────────────────────┬──────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│             PERMISSION TIER SETUP                   │
│                                                     │
│   "How much would you like me to observe?"         │
│                                                     │
│   ○ Passive Only — I'll speak when spoken to       │
│   ○ App Awareness — Know what app you're in        │
│   ● Context Mode — Suggest when I see opportunity  │
│   ○ Full Automation — Take action on my behalf     │
│                                                     │
│   [What does each mean? ▼]                        │
│                                                     │
│   [Start Conservative — I can expand later]       │
│                    [Continue]                       │
└──────────────────────────┬──────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│              API KEY SETUP                          │
│                                                     │
│   "I need your Claude API key to think."           │
│   Your key stays on your device. Always.           │
│                                                     │
│   [ ••••••••••••••••••••••  ] [Paste]              │
│                                                     │
│   [Get a key from Anthropic →]                    │
│   [I'll set this up later]                         │
│                    [Verify & Continue]              │
└──────────────────────────┬──────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│              INTERACTIVE TUTORIAL                   │
│                                                     │
│   BUTLER demonstrates:                             │
│   1. Proactive suggestion → user responds          │
│   2. Push-to-talk → ask question → voice response  │
│   3. Dismiss option → "Got it, noted."             │
│   4. Global mute (keyboard shortcut demo)          │
│                                                     │
│   [Skip Tutorial]       [Complete Setup]           │
└──────────────────────────┬──────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│                MAIN EXPERIENCE BEGINS               │
│   Glass Chamber in idle state, corner of screen    │
└─────────────────────────────────────────────────────┘
```

---

## 2. Proactive Intervention Flow

### 2.1 Trigger → Suggestion → Response

```
┌──────────────────────────────────────────────────────────────┐
│                 BACKGROUND: Activity Monitor                 │
│   Downloads folder: 147 files, oldest = 12 days ago         │
└──────────────────────────────┬───────────────────────────────┘
                               │ Context event emitted
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                 Context Analyzer evaluates                   │
│   Rule: downloads_clutter                                    │
│   Base weight: 0.7                                           │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                 Decision Engine scores                       │
│   Context weight:  0.70                                      │
│   User tolerance:  0.72 (72/100)                            │
│   Time modifier:   1.00 (2 PM, work hours)                  │
│   Frequency decay: 1.00 (not triggered recently)            │
│   ─────────────────────────────                             │
│   Score = 0.70 × 0.72 × 1.00 × 1.00 = 0.504               │
│                                                              │
│   ← Score < 0.65 threshold                                  │
│   ── SUPPRESSED (not triggered)                             │
└──────────────────────────────────────────────────────────────┘

[Later: user engagement rate increases, tolerance rises to 82]

┌──────────────────────────────────────────────────────────────┐
│   Score = 0.70 × 0.82 × 1.00 × 1.00 = 0.574               │
│   Still suppressed. Next day, file count grows to 160.      │
│   Rule re-weights base to 0.85                              │
│   Score = 0.85 × 0.82 × 1.00 × 1.00 = 0.697 ✓ FIRES      │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│   SUPPRESSION CHECK (hardcoded safety rules)                │
│   ✓ No video call active                                    │
│   ✓ No screen share active                                  │
│   ✓ Not fullscreen app                                      │
│   ✓ Not in Quiet Hours                                      │
│   ✓ Focus Mode: OFF                                         │
│   → PROCEED                                                 │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                 INTERVENTION DELIVERED                       │
│                                                             │
│   Glass Chamber:  Expands 10% from idle size               │
│   Pulse:          Idle (white) → Gold (conversational)      │
│   Sound:          Soft chime (subtle, not jarring)          │
│   Voice:          "Your Downloads folder has 160 unsorted   │
│                    files. Shall I categorize them?"         │
│   Chat bubble:    Same text appears in conversation panel   │
└──────────────────────────────┬───────────────────────────────┘
                               │
                  ┌────────────┴────────────┐
                  │                         │
                  ▼                         ▼
    ┌─────────────────────┐    ┌─────────────────────────────┐
    │    USER ENGAGES     │    │       USER DISMISSES        │
    │                     │    │                             │
    │  Voice: "Yes, sort  │    │  Click X  or               │
    │   by type"          │    │  Say "Not now"  or          │
    │  OR                 │    │  No response (ignored)      │
    │  Click "Yes"        │    └──────────────┬──────────────┘
    └──────────┬──────────┘                   │
               │                              ▼
               ▼                 ┌────────────────────────┐
    ┌──────────────────────┐     │  Was this dismissed    │
    │  Pulse → Blue        │     │  3+ times this week?   │
    │  (Thinking)          │     └────────────┬───────────┘
    │  Claude reasons      │                  │
    │  File plan formed    │          ┌───────┴────────┐
    │  Pulse → Gold        │          │                │
    │  (Speaking)          │          ▼                ▼
    │  "I'll organize by   │     ┌─────────┐    ┌──────────────┐
    │   type, then date.   │     │   NO    │    │    YES       │
    │   Proceeding."       │     │ Decay   │    │ Auto-suppress│
    │  Pulse → Green       │     │ score   │    │ trigger for  │
    │  (Success flash)     │     │ slightly│    │ 7 days       │
    └──────────────────────┘     └─────────┘    └──────────────┘
```

---

## 3. User-Initiated Voice Interaction Flow

```
┌──────────────────────────────────────────────────────────────┐
│                  USER HOLDS HOTKEY (⌘ Space)                 │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│   Pulse state: Idle → Listening (white + ripple)            │
│   Microphone: Active                                         │
│   Status bar: "Listening..."                                 │
└──────────────────────────────┬───────────────────────────────┘
                               │ User speaks
                               ▼
┌──────────────────────────────────────────────────────────────┐
│   User: "Organize my project files into folders by type"     │
└──────────────────────────────┬───────────────────────────────┘
                               │ User releases hotkey
                               ▼
┌──────────────────────────────────────────────────────────────┐
│   STT finalizes transcript                                   │
│   Pulse: Listening → Thinking (blue, expanding waves)       │
│   Status bar: "Thinking..."                                  │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│   Claude API called (streaming)                              │
│   System prompt: Personality + behavioral profile           │
│   Message: User's voice input                               │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│   Streaming response begins                                  │
│   Pulse: Thinking → Speaking (gold, synced to TTS)          │
│   Status bar: "Alfred"                                       │
│   Voice: "To organize your project files, I'll need to know │
│            which folder you're working in."                  │
│   Conversation panel: Text appears as voice plays            │
└──────────────────────────────┬───────────────────────────────┘
                               │
                        ┌──────┴──────┐
                        │             │
                        ▼             ▼
              ┌──────────────┐  ┌──────────────────┐
              │  BUTLER asks │  │  Action requires  │
              │  follow-up   │  │  confirmation    │
              │  question    │  │                  │
              │              │  │  "I'll create:   │
              │  → Continue  │  │  /Images         │
              │    dialogue  │  │  /Documents      │
              │              │  │  /Code           │
              │              │  │  Proceed? [Yes/No]│
              └──────────────┘  └──────────────────┘
```

---

## 4. Settings Panel Flow

```
Glass Chamber
└── Settings Icon (gear)
    │
    ├── Personality Tab
    │   ├── Name field
    │   ├── Formality slider (1–5)
    │   ├── Proactivity slider (1–5)
    │   ├── Humor slider (1–5)
    │   ├── Directness slider (1–5)
    │   └── Custom prompt injection textarea
    │
    ├── Voice Tab
    │   ├── Voice preset selector
    │   ├── [Play sample] button
    │   ├── Speed slider (0.75x – 1.5x)
    │   ├── Pitch adjustment (if native TTS)
    │   └── ElevenLabs API key field (optional)
    │
    ├── Permissions Tab
    │   ├── Tier 0: Always available (radio)
    │   ├── Tier 1: App Awareness (toggle)
    │   │   └── Browser domain detection (sub-toggle)
    │   ├── Tier 2: Context (individual toggles)
    │   │   ├── Downloads folder
    │   │   ├── Idle detection
    │   │   ├── Calendar presence
    │   │   └── File metadata
    │   ├── Tier 3: Automation (locked until Tier 2 active 7 days)
    │   ├── Site Exclusion List (text + add/remove)
    │   ├── App Exclusion List (text + add/remove)
    │   └── Re-confirm permissions [button]
    │
    ├── Automation Tab
    │   ├── Approved shortcuts list
    │   ├── Approved scripts list (with view button)
    │   └── Action history [View Log]
    │
    ├── Privacy Tab
    │   ├── Quiet Hours (time range picker)
    │   ├── Conversation history (list + delete)
    │   ├── Behavioral profile [View] [Reset]
    │   ├── Export all data [JSON download]
    │   └── Delete all data [confirmation required]
    │
    └── Appearance Tab
        ├── Chamber transparency (slider)
        ├── Chamber size (compact / normal / large)
        ├── Corner pinning (top-left / top-right / bottom-left / bottom-right)
        ├── Auto-hide delay (5s / 15s / 30s / never)
        ├── Pulse skin selector (default + premium)
        └── Dark / Light theme override
```

---

## 5. Dismissal Interaction Patterns

```
BUTLER Suggestion bubble appears

┌────────────────────────────────────────────┐
│  "Your Downloads has 160 files.            │
│   Shall I organize them?"                  │
│                                            │
│  [Yes, sort them]  [Not now]  [✕]         │
│                    [Never ask about this]  │
└────────────────────────────────────────────┘

User options:
│
├── [Yes, sort them]
│   → Proceeds to confirmation flow
│   → Tolerance score +3
│
├── [Not now]
│   → Dismissed for this session
│   → Tolerance score -2
│   → Trigger cooldown resets
│
├── [✕] (X button)
│   → Same as "Not now" but faster
│
└── [Never ask about this]
    → Permanent rule suppression for this trigger type
    → Stored in suppressed_triggers table
    → BUTLER: "Noted. I won't bring this up again."
    → Tolerance score -1 (soft penalty)
```

---

## 6. Automation Confirmation Flow (Tier 3)

```
┌──────────────────────────────────────────────────────────┐
│   BUTLER proposes an action                             │
│                                                          │
│   "I'll move 34 files from Downloads to these folders:  │
│    Images/ — 12 files                                    │
│    Documents/ — 8 files                                  │
│    Installers/ — 14 files                                │
│                                                          │
│    Shall I proceed?"                                     │
│                                                          │
│   [Confirm]  [Modify Plan]  [Cancel]                    │
└──────────────────────┬───────────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │ CONFIRM  │ │  MODIFY  │ │  CANCEL  │
    │          │ │          │ │          │
    │ Execute  │ │ Opens    │ │ No action│
    │ action   │ │ editable │ │ Pulse →  │
    │          │ │ plan     │ │ Idle     │
    │ Log it   │ │ in chat  │ │          │
    │          │ │ panel    │ │          │
    │ Undo     │ │          │ │          │
    │ window   │ │ Re-      │ │          │
    │ (30s)    │ │ confirm  │ │          │
    └────┬─────┘ └──────────┘ └──────────┘
         │
         ▼
┌──────────────────────┐
│  UNDO WINDOW (30s)   │
│                      │
│  "Done. 34 files     │
│   organized."        │
│                      │
│  [Undo ◄] 27s        │
└──────────────────────┘
```

---

## 7. Focus Mode & Global Mute Flow

```
GLOBAL MUTE (keyboard shortcut)
         │
         ▼
┌──────────────────────────────────────┐
│  All suggestions: SILENCED           │
│  Voice output: SILENCED              │
│  Pulse: Dim white, minimal breathing │
│  Status indicator: "Muted"           │
│  Quick tap same key to unmute        │
└──────────────────────────────────────┘

FOCUS MODE (Glass Chamber quick control)
         │
         ▼
┌──────────────────────────────────────┐
│  Proactive suggestions: OFF          │
│  Voice input: Still available        │
│  BUTLER responds when spoken to      │
│  Pulse: Subtle blue tint (focus mode │
│          indicator)                  │
│  Status: "Focus Mode Active"         │
│  Duration: Until toggled off         │
└──────────────────────────────────────┘

QUIET HOURS (scheduled)
         │
         ▼
┌──────────────────────────────────────┐
│  Activates automatically at set time │
│  Behaves like Global Mute            │
│  Voice input: Still available        │
│  Pulse: Dim, no glow                 │
│  Auto-lifts at end of quiet window   │
└──────────────────────────────────────┘
```

---

## 8. Glass Chamber Window State Transitions

```
COLLAPSED ORB (corner)
   8px pulsing orb, minimal CPU
   Click → IDLE STATE

IDLE STATE
   Small vertical panel
   Pulse floating, breathing
   Quick controls visible
   Hover → shows status bar

ACTIVE STATE (BUTLER speaking/processing)
   Expands 10–15% from idle
   Pulse enlarges
   Status bar shows current state

CONVERSATION MODE
   Chat panel slides in from right (or below on narrow screens)
   Conversation history visible
   Input bar at bottom
   Pulse reduced in size, still visible

SETTINGS MODE
   Full expansion to settings width
   Tabs visible
   Pulse minimized to small orb in top corner
   Click pulse to return to conversation

MINIMIZED (auto-hide active)
   1px glowing edge on screen border
   Mouse proximity → fade in to IDLE
```

---

## 9. Error & Edge Case UI States

```
STT Not Available (no microphone permission)
   → Pulse: Amber alert
   → Message: "Microphone access is needed for voice interaction. Enable in System Settings?"
   → [Open Settings] [Use Chat Only]

API Key Invalid
   → Pulse: Red concerned state
   → Message: "I can't reach my thinking layer. Please check your API key."
   → [Open Settings → API Key] [Try Again]

No Internet (API unreachable)
   → Message: "I'm offline — chat and local features still work."
   → Voice fallback: macOS native TTS only
   → Suggestions: Rule-based only (no Claude)

Video Call Detected
   → Pulse: Dims silently to near-invisible
   → All suggestions suppressed
   → Resumes automatically when call ends

Low Memory Warning
   → BUTLER suspends background monitoring
   → Notification: "I've reduced activity to help your Mac breathe."

Crash Recovery
   → On next launch: "I had to restart. I've recovered our conversation."
   → Conversation history restored from database
```

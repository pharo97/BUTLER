# PRD-06: BUTLER — Feature Prioritization Matrix

**Version:** 2.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Product / Engineering

> **Cross-references:** PRD-11 (CLI command inventory) | PRD-12 (IPC architecture) | PRD-13 (distribution strategy) | PRD-14 (code signing pipeline)

---

## 1. Prioritization Framework

Features are scored across three dimensions:

| Dimension | Weight | Description |
|-----------|--------|-------------|
| **User Value** | 40% | Direct impact on user experience and retention |
| **Technical Feasibility** | 30% | Effort, risk, and dependency complexity |
| **Business Impact** | 30% | Revenue, acquisition, and differentiation |

Score = (User Value × 0.4) + (Feasibility × 0.3) + (Business × 0.3)
Each dimension scored 1–10. Final score out of 10.

---

## 2. Full Feature Inventory & Scores

### Core Infrastructure

| Feature | User Value | Feasibility | Business | **Score** | Phase |
|---------|-----------|-------------|---------|-----------|-------|
| Glass Chamber UI (idle + orb) | 9 | 8 | 9 | **8.7** | P1 |
| Push-to-talk voice input | 9 | 9 | 8 | **8.7** | P1 |
| Claude API integration (streaming) | 10 | 9 | 10 | **9.7** | P1 |
| Native TTS voice output | 9 | 9 | 8 | **8.7** | P1 |
| Personality configuration UI | 8 | 8 | 8 | **8.0** | P1 |
| Pulse animation (idle + speaking) | 8 | 7 | 9 | **8.0** | P1 |
| Local SQLite behavioral store | 7 | 8 | 7 | **7.3** | P1 |
| API key management (Keychain) | 9 | 9 | 8 | **8.7** | P1 |
| Global mute / keyboard shortcut | 8 | 9 | 7 | **8.0** | P1 |
| Onboarding flow | 8 | 8 | 9 | **8.3** | P1 |

### Context & Intelligence

| Feature | User Value | Feasibility | Business | **Score** | Phase |
|---------|-----------|-------------|---------|-----------|-------|
| Active app detection (Tier 1) | 7 | 9 | 7 | **7.6** | P1 |
| Browser domain detection | 7 | 7 | 7 | **7.0** | P2 |
| Downloads folder monitoring | 8 | 8 | 7 | **7.7** | P2 |
| Idle time detection | 7 | 9 | 6 | **7.3** | P2 |
| Suggestion/intervention engine | 9 | 7 | 8 | **8.0** | P2 |
| Reinforcement scoring (tolerance) | 8 | 7 | 8 | **7.7** | P2 |
| Anti-annoyance logic | 9 | 8 | 9 | **8.7** | P2 |
| Behavioral memory persistence | 8 | 7 | 8 | **7.7** | P2 |
| Intervention score formula | 8 | 8 | 7 | **7.7** | P2 |
| Calendar presence detection | 6 | 7 | 6 | **6.3** | P2 |
| Late-night / time-of-day modifier | 7 | 9 | 6 | **7.3** | P2 |
| Focus mode | 9 | 9 | 8 | **8.7** | P2 |
| Quiet hours scheduling | 8 | 9 | 7 | **8.0** | P2 |
| Site/app exclusion lists | 8 | 9 | 8 | **8.3** | P2 |

### Automation & Execution

| Feature | User Value | Feasibility | Business | **Score** | Phase |
|---------|-----------|-------------|---------|-----------|-------|
| File move / organize | 8 | 7 | 8 | **7.7** | P3 |
| File rename | 7 | 8 | 6 | **7.0** | P3 |
| Open / close apps | 7 | 8 | 7 | **7.3** | P3 |
| Create folders | 8 | 9 | 7 | **8.0** | P3 |
| Trash files (no permanent delete) | 7 | 8 | 6 | **7.0** | P3 |
| AppleScript execution (sandboxed) | 7 | 6 | 7 | **6.7** | P3 |
| Shortcuts integration | 8 | 8 | 8 | **8.0** | P3 |
| Draft email (compose, not send) | 7 | 7 | 7 | **7.0** | P3 |
| Calendar event creation | 6 | 7 | 6 | **6.3** | P3 |
| Undo window (30s) | 8 | 7 | 7 | **7.3** | P3 |
| Automation action log | 8 | 8 | 7 | **7.7** | P3 |

### Voice & Personalization

| Feature | User Value | Feasibility | Business | **Score** | Phase |
|---------|-----------|-------------|---------|-----------|-------|
| Voice preset selection (4 styles) | 8 | 9 | 8 | **8.3** | P1 |
| Voice speed/tone control | 7 | 9 | 6 | **7.3** | P2 |
| ElevenLabs premium voices | 7 | 7 | 8 | **7.3** | P2 |
| Wake word detection | 7 | 6 | 7 | **6.7** | P3 |
| Custom voice personality prompt | 8 | 8 | 7 | **7.7** | P2 |
| Pulse skin themes | 6 | 7 | 8 | **6.9** | P3 |
| Visual pulse evolution | 6 | 6 | 7 | **6.3** | P3 |
| Audio-reactive animation | 8 | 6 | 8 | **7.4** | P2 |
| Conversation history (chat panel) | 8 | 8 | 7 | **7.7** | P1 |
| Export conversation | 6 | 8 | 6 | **6.6** | P2 |

### Safety & Control

| Feature | User Value | Feasibility | Business | **Score** | Phase |
|---------|-----------|-------------|---------|-----------|-------|
| Video call auto-suppression | 10 | 7 | 10 | **9.1** | P1 |
| Screen share detection | 9 | 6 | 9 | **8.1** | P2 |
| Fullscreen suppression | 9 | 8 | 8 | **8.5** | P1 |
| Permission dashboard | 9 | 8 | 9 | **8.7** | P1 |
| 90-day permission re-confirmation | 7 | 8 | 7 | **7.3** | P2 |
| Data export (JSON) | 7 | 8 | 7 | **7.3** | P2 |
| Full data deletion | 8 | 9 | 8 | **8.3** | P1 |
| Sensitivity slider | 8 | 9 | 8 | **8.3** | P2 |

### Platform & Distribution

| Feature | User Value | Feasibility | Business | **Score** | Phase |
|---------|-----------|-------------|---------|-----------|-------|
| Auto-update (Sparkle) | 7 | 8 | 8 | **7.7** | P1 |
| Direct download (DMG) distribution | 8 | 9 | 9 | **8.6** | P1 |
| Code signing + notarization | 10 | 8 | 10 | **9.4** | P1 |
| Sparkle EdDSA update signing | 8 | 8 | 7 | **7.7** | P1 |
| Mac App Store build | 6 | 6 | 8 | **6.6** | P3 |
| Subscription management (Stripe) | 7 | 7 | 9 | **7.6** | P2 |
| BYOK billing tier | 8 | 8 | 8 | **8.0** | P1 |
| Integrated billing tier ($30–40) | 7 | 6 | 9 | **7.3** | P2 |
| CLI interface (`butler` commands) | 8 | 8 | 8 | **8.0** | P3 |
| IPC daemon integration (Unix socket) | 7 | 7 | 7 | **7.0** | P3 |
| Homebrew formula (CLI tap) | 7 | 8 | 8 | **7.7** | P3 |
| Terminal installer (curl \| bash) | 7 | 8 | 7 | **7.3** | P3 |
| iOS Companion app | 8 | 4 | 9 | **7.1** | P4 |
| Notification sync (Mac → iOS) | 7 | 5 | 8 | **6.7** | P4 |

---

## 3. Phase-Bucketed Priority List

### Phase 1 (MVP — Weeks 1–8)
*Must ship for a compelling first experience*

| Priority | Feature | Score |
|----------|---------|-------|
| 1 | Claude API integration (streaming) | 9.7 |
| 2 | Code signing + notarization | 9.4 |
| 3 | Video call auto-suppression | 9.1 |
| 4 | Glass Chamber UI | 8.7 |
| 5 | Push-to-talk voice input | 8.7 |
| 6 | Native TTS voice output | 8.7 |
| 7 | Anti-annoyance logic | 8.7 |
| 8 | API key management | 8.7 |
| 9 | Permission dashboard | 8.7 |
| 10 | Focus mode | 8.7 |
| 11 | Direct download (DMG) distribution | 8.6 |
| 12 | Fullscreen suppression | 8.5 |
| 13 | Onboarding flow | 8.3 |
| 14 | Voice preset selection | 8.3 |
| 15 | Site/app exclusion lists | 8.3 |
| 16 | Full data deletion | 8.3 |
| 17 | Global mute | 8.0 |
| 18 | Pulse animation (idle + speaking) | 8.0 |
| 19 | Personality configuration UI | 8.0 |
| 20 | BYOK billing tier | 8.0 |
| 21 | Conversation history panel | 7.7 |
| 22 | Auto-update (Sparkle) | 7.7 |
| 23 | Sparkle EdDSA update signing | 7.7 |
| 24 | Local SQLite store | 7.3 |

### Phase 2 (Ambient Intelligence — Weeks 9–14)

| Priority | Feature | Score |
|----------|---------|-------|
| 1 | Suggestion/intervention engine | 8.0 |
| 2 | Quiet hours | 8.0 |
| 3 | Reinforcement scoring | 7.7 |
| 4 | Behavioral memory | 7.7 |
| 5 | Downloads folder monitoring | 7.7 |
| 6 | Intervention score formula | 7.7 |
| 7 | Screen share detection | 8.1 |
| 8 | Audio-reactive animation | 7.4 |
| 9 | Active app detection | 7.6 |
| 10 | Sensitivity slider | 8.3 |
| 11 | Idle detection | 7.3 |
| 12 | Late-night time modifier | 7.3 |
| 13 | Voice speed/tone control | 7.3 |
| 14 | ElevenLabs integration | 7.3 |
| 15 | Custom voice personality | 7.7 |
| 16 | Browser domain detection | 7.0 |
| 17 | Subscription management | 7.6 |
| 18 | Integrated billing tier | 7.3 |
| 19 | 90-day permission re-confirm | 7.3 |
| 20 | Data export | 7.3 |

### Phase 3 (OS Control — Weeks 15–22)

| Priority | Feature | Score |
|----------|---------|-------|
| 1 | Create folders | 8.0 |
| 2 | Shortcuts integration | 8.0 |
| 3 | CLI interface (`butler` commands) | 8.0 |
| 4 | File move / organize | 7.7 |
| 5 | Automation action log | 7.7 |
| 6 | Homebrew formula (CLI tap) | 7.7 |
| 7 | Undo window | 7.3 |
| 8 | Open / close apps | 7.3 |
| 9 | Terminal installer (curl \| bash) | 7.3 |
| 10 | File rename | 7.0 |
| 11 | Trash files | 7.0 |
| 12 | Draft email | 7.0 |
| 13 | IPC daemon integration | 7.0 |
| 14 | AppleScript execution | 6.7 |
| 15 | Wake word detection | 6.7 |
| 16 | Pulse skin themes | 6.9 |
| 17 | Calendar event creation | 6.3 |
| 18 | Mac App Store build | 6.6 |

### Phase 4 (iOS — Weeks 23+)

| Feature | Score |
|---------|-------|
| iOS Companion app | 7.1 |
| Notification sync | 6.7 |
| Voice-only iOS mode | 7.0 |
| Continuity handoff | 6.5 |

---

## 4. MVP Definition (Must-Have vs. Nice-to-Have)

### Must-Have for v1.0 launch
- Claude streaming API ✓
- Push-to-talk + TTS voice ✓
- Glass Chamber UI (idle + orb states) ✓
- Pulse animation (basic states) ✓
- Personality config (name, presets) ✓
- Permission dashboard ✓
- Video call / fullscreen suppression ✓
- Global mute ✓
- Onboarding flow ✓
- API key setup ✓
- Conversation panel ✓
- Full data deletion ✓
- Direct download (DMG) distribution ✓
- Code signing + notarization (required for Gatekeeper) ✓
- Sparkle auto-update with EdDSA signing ✓
- BYOK subscription billing ✓

### Nice-to-Have for v1.0 (ship if time permits)
- Downloads folder monitoring
- Basic intervention engine (one trigger type)
- Focus mode
- Audio-reactive animation
- ElevenLabs integration

### Definitely Post-v1.0
- All Tier 3 automation features
- Wake word
- Pulse skins / themes
- iOS app
- Mac App Store build

---

## 5. Feature Dependencies

```
Claude API → [Everything AI-related]
Glass Chamber UI → [All user interaction]
Permission Dashboard → [Tier 1, 2, 3 features]
SQLite Store → [Behavioral memory, conversation history]
Behavioral Memory → [Intervention engine, reinforcement scoring]
Intervention Engine → [All proactive suggestions]
Anti-annoyance logic → [Intervention engine]
Activity Monitor → [All Tier 1/2 signals]
Context Analyzer → [Intervention engine]
Tier 2 permissions → [Tier 3 features (7-day gate)]
Automation action log → [All Tier 3 actions]
Code signing + notarization → [DMG distribution, Sparkle auto-update, Gatekeeper approval]
CLI Controller Module → [IPC Unix socket server, all butler command dispatch]
IPC socket → [butler status, butler speak, butler config, butler history, butler logs, etc.]
Homebrew formula → [butler CLI binary tap distribution]
Terminal installer → [curl | bash deployment path]
```

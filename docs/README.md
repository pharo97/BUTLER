# BUTLER — PRD Documentation Index

**Project:** BUTLER — AI Operating Companion for macOS
**Version:** 2.0
**Last Updated:** 2026-03-03

---

## Document Index

| # | Document | Description |
|---|----------|-------------|
| 01 | [PRD-01-Product-Requirements.md](PRD-01-Product-Requirements.md) | Full Product Requirements Document — features, personas, permissions, CLI interface, distribution, monetization, success metrics |
| 02 | [PRD-02-Technical-Architecture.md](PRD-02-Technical-Architecture.md) | System architecture, 11-module specs, inter-module API contracts, IPC protocol, tech stack, performance targets |
| 03 | [PRD-03-Security-Permissions.md](PRD-03-Security-Permissions.md) | Permission tier model, data security, privacy threat model, IPC auth, compliance (GDPR/CCPA), incident response |
| 04 | [PRD-04-macOS-API-Integration.md](PRD-04-macOS-API-Integration.md) | macOS API integration strategy — NSPanel, Accessibility API, FSEvents, EventKit, Speech, AppleScript |
| 05 | [PRD-05-UX-Flows.md](PRD-05-UX-Flows.md) | UX flow diagrams — onboarding, intervention, voice interaction, settings, dismissal, edge cases |
| 06 | [PRD-06-Feature-Prioritization.md](PRD-06-Feature-Prioritization.md) | Feature scoring matrix, phase-bucketed priority list, MVP definition, CLI + distribution features, dependency map |
| 07 | [PRD-07-Risk-Compliance.md](PRD-07-Risk-Compliance.md) | Risk register (19 risks), compliance analysis (App Store, GDPR, CCPA, ADA), incident response plan |
| 08 | [PRD-08-Engineering-Sprint-Plan.md](PRD-08-Engineering-Sprint-Plan.md) | 24-week sprint plan (12 sprints) — detailed tasks, definitions of done, CLI/distribution/edge case sprints |
| 09 | [PRD-09-Go-To-Market.md](PRD-09-Go-To-Market.md) | GTM strategy — market segments, launch channels, pricing, retention, press, 90-day metrics |
| 10 | [PRD-10-Investor-Pitch.md](PRD-10-Investor-Pitch.md) | Investor pitch summary — problem, solution, market size, unit economics, projections, ask |
| 11 | [PRD-11-CLI-Specification.md](PRD-11-CLI-Specification.md) | Complete `butler` CLI command reference — syntax, flags, output contracts, exit codes, tab completion |
| 12 | [PRD-12-CLI-Module-Architecture.md](PRD-12-CLI-Module-Architecture.md) | Two-binary model, `butlerd` daemon design, Unix domain socket IPC protocol, message schema, auth model |
| 13 | [PRD-13-Installation-Distribution.md](PRD-13-Installation-Distribution.md) | DMG drag-and-drop spec, terminal installer script, Homebrew formula/cask, Sparkle update pipeline |
| 14 | [PRD-14-Code-Signing-Notarization.md](PRD-14-Code-Signing-Notarization.md) | Developer ID certificates, signing entitlements, notarytool pipeline, stapling, GitHub Actions CI/CD |
| 15 | [PRD-15-Modular-Architecture.md](PRD-15-Modular-Architecture.md) | All 11 modules: responsibilities, inputs, outputs, dependencies, communication patterns, prohibited behaviors |
| 16 | [PRD-16-Data-Flow-Diagrams.md](PRD-16-Data-Flow-Diagrams.md) | Text-based data flow diagrams for all 9 pipelines (voice, context, CLI→IPC, automation, memory, etc.) |
| 17 | [PRD-17-Resource-Management.md](PRD-17-Resource-Management.md) | CPU/RAM/GPU budgets per module, thermal throttling, memory pressure response, latency targets |
| 18 | [PRD-18-Anti-Intrusiveness-Framework.md](PRD-18-Anti-Intrusiveness-Framework.md) | 7-tier suppression hierarchy, hardcoded kill switches, intervention scoring formula, backoff algorithms |
| 19 | [PRD-19-Edge-Case-Handling.md](PRD-19-Edge-Case-Handling.md) | 40-item edge case catalog across 9 domains with implementation requirements and QA checklist |

---

## Key Decisions at a Glance

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Platform | Swift + SwiftUI (macOS 14+) | Native performance, Accessibility API, Metal |
| Animation | WebGL/Three.js (Phase 1) → Metal (Phase 2) | Iteration speed first, then performance |
| AI Backend | Claude API (streaming) | Reasoning quality, streaming support |
| STT | Apple SFSpeechRecognizer | On-device, private, fast |
| Storage | SQLite + SQLCipher (AES-256) | Local-first, encrypted, no server |
| Distribution | DMG (v1.0) → Homebrew (v1.1) → App Store (v2.0) | Single channel until stable; App Store deferred (sandbox limitations) |
| Code signing | Developer ID Application certificate + notarytool | Required for Gatekeeper; no right-click bypass for users |
| CLI architecture | Two-binary: BUTLER.app (socket server) + `butler` (thin client) | No separate daemon process; app IS the daemon |
| IPC protocol | Unix domain socket (0600) + session auth token | Local-only, OS-enforced permissions, no network exposure |
| CLI distribution | Homebrew tap + terminal installer (curl \| bash) | Developer-friendly; does not require GUI install |
| Default permission | Tier 0 (passive) | Trust-first design |
| Pricing (BYOK) | $12/mo or $99/yr | Low friction entry |
| Pricing (Integrated) | $35/mo or $299/yr | Bundled Claude API |

---

## Critical Design Principles

1. The line between genius and spyware is consent and transparency.
2. Fewer, better suggestions > constant chatter.
3. Abstract animation > humanoid (luxury, not uncanny).
4. Latency target: <1.5s from speech end to first TTS word.
5. BUTLER never interrupts: video calls, screen share, fullscreen, presentations.
6. All behavioral data stays on device. Always.

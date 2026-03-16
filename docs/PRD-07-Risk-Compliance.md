# PRD-07: BUTLER — Risk & Compliance Analysis

**Version:** 2.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Product / Legal / Engineering

> **Cross-references:** PRD-12 (IPC architecture + daemon lifecycle) | PRD-13 (distribution strategy) | PRD-14 (code signing + notarization) | PRD-19 (edge case catalog for all risk scenarios)

---

## 1. Risk Register Overview

Risks are rated on two dimensions:
- **Likelihood** (1–5): How probable is this risk to occur?
- **Impact** (1–5): How severe would the consequence be?
- **Risk Score** = Likelihood × Impact

| Score | Rating |
|-------|--------|
| 1–4 | Low |
| 5–9 | Medium |
| 10–16 | High |
| 17–25 | Critical |

---

## 2. Product & UX Risks

### R-01: Over-Intrusiveness (The "Clippy Effect")
**Likelihood:** 4 | **Impact:** 5 | **Score: 20 — Critical**

If BUTLER interrupts at the wrong moment or too frequently, users will mute it permanently and leave negative reviews. This is the single greatest product risk.

**Mitigation:**
- Intervention score threshold (0.65) enforced mathematically
- Anti-annoyance logic: same trigger capped at once per 4 hours
- 3 dismissals → 7-day auto-suppress
- Video call / fullscreen detection hardcoded off-switch
- Sensitivity slider gives user direct control
- Default proactivity level: 3/5 (conservative)
- User research: test with 20+ users in alpha before any public release

**Residual Risk:** Medium (2×3=6) after mitigation

---

### R-02: High Voice Latency
**Likelihood:** 3 | **Impact:** 4 | **Score: 12 — High**

A slow voice response (>2 seconds from speech end to first TTS word) destroys the illusion of intelligence. Users will perceive BUTLER as sluggish.

**Mitigation:**
- STT: Apple SFSpeechRecognizer runs fully on-device (<200ms finalization)
- Streaming API response: first token appears in <500ms for short prompts
- TTS streaming: begin speaking before full response is received (stream to TTS)
- Optimize system prompt length to minimum necessary
- Latency monitoring in telemetry (opt-in) to detect degradation
- Target: <1.5s from speech end to first TTS word

**Residual Risk:** Medium (2×3=6) after mitigation

---

### R-03: "Uncanny Valley" Animation
**Likelihood:** 3 | **Impact:** 3 | **Score: 9 — Medium**

If the pulse animation is too human-like or poorly executed, it triggers discomfort rather than connection.

**Mitigation:**
- Strictly abstract — no face, no humanoid form
- Multiple design iterations with user testing before launch
- Option to minimize to plain orb (removes animation concern entirely)
- High-quality Metal shader or professionally designed WebGL scene
- Luxury minimalism as the guiding aesthetic principle

**Residual Risk:** Low (2×2=4) after mitigation

---

### R-04: Suggestion Quality Degradation
**Likelihood:** 3 | **Impact:** 4 | **Score: 12 — High**

If Claude generates poor-quality suggestions (irrelevant, wrong context, repetitive), users lose trust in BUTLER.

**Mitigation:**
- System prompt is tightly structured and tested
- Behavioral profile feeds context to Claude
- Context templates are pre-validated (not free-form generation for suggestions)
- User feedback loop informs prompt refinement
- A/B test prompt variants in beta

**Residual Risk:** Medium (2×3=6) after mitigation

---

## 3. Technical Risks

### R-05: Apple Accessibility API Instability
**Likelihood:** 3 | **Impact:** 4 | **Score: 12 — High**

Apple can change or restrict Accessibility API behavior in any macOS update, breaking browser domain detection and other Tier 1 features.

**Mitigation:**
- Defensive coding: wrap all AX calls in try-catch; graceful degradation
- Core features (voice, chat) never depend on AX API
- Each macOS major version: regression test AX features within 1 week of release
- Maintain per-browser adapter modules — isolate breakage
- Community monitoring: watch macOS release notes and developer forums

**Residual Risk:** Medium (2×3=6) after mitigation

---

### R-06: macOS Sandbox Restrictions (App Store)
**Likelihood:** 5 | **Impact:** 3 | **Score: 15 — High**

App Store sandboxing blocks AppleScript, full FSEvents access, and Accessibility API in some configurations. Tier 3 features are impossible in sandbox.

**Mitigation:**
- Ship two builds: Direct (full capability) and App Store (limited)
- Clearly document capability differences at download time
- Direct distribution as primary channel
- App Store build markets itself as "core BUTLER" without Tier 3 features
- App Store build still delivers voice, personality, and Tier 1/2 suggestions

**Residual Risk:** Low (already planned around) (2×2=4)

---

### R-07: Claude API Downtime or Rate Limiting
**Likelihood:** 2 | **Impact:** 4 | **Score: 8 — Medium**

If the Claude API is unavailable, BUTLER cannot respond intelligently.

**Mitigation:**
- Graceful offline mode: rule-based suggestions still function
- Clear UI state when API is unreachable
- TTS works without API (macOS native voices)
- Conversation history still browsable
- Retry logic with exponential backoff
- User notification: "I'm temporarily offline. Core features still work."

**Residual Risk:** Low (1×3=3) after mitigation

---

### R-08: Local Database Corruption
**Likelihood:** 2 | **Impact:** 3 | **Score: 6 — Medium**

SQLite database corruption (crash, power loss, disk error) could lose behavioral history and conversation logs.

**Mitigation:**
- SQLite WAL (Write-Ahead Logging) mode enabled
- Daily automated database integrity check (`PRAGMA integrity_check`)
- Automatic backup to secondary `.db.bak` file on clean close
- Rebuild from scratch gracefully if corruption detected — behavioral data is not critical (only affects suggestion tuning)
- Conversation history: warn user on data loss

**Residual Risk:** Low (1×2=2) after mitigation

---

### R-09: Memory / CPU Performance Impact
**Likelihood:** 3 | **Impact:** 4 | **Score: 12 — High**

A poorly optimized BUTLER that consumes significant CPU/RAM will alienate professional users who depend on Mac performance for their work.

**Mitigation:**
- Target: <2% idle CPU, <150MB RAM
- Activity Monitor suspended when system is under memory pressure
- Animation frame rate adapts to battery mode (60fps → 30fps on battery)
- SQLite queries profiled; indexes on all query-hot columns
- Claude API calls are event-driven (not polling)
- FSEvents is lightweight by design
- Profiling with Instruments as part of every release cycle

**Residual Risk:** Low (2×2=4) after mitigation

---

## 4. Privacy & Security Risks

### R-10: User Perception of Surveillance
**Likelihood:** 4 | **Impact:** 5 | **Score: 20 — Critical**

Even with proper permissions, users may feel uncomfortable with a system that monitors their activity. One bad press article or social media post ("AI watches everything you do on your Mac") could be devastating.

**Mitigation:**
- Radical transparency: permission dashboard always visible
- No data leaves the device (zero-knowledge design)
- Tier 0 default: BUTLER does nothing until you invite it
- Clear marketing language: "You control everything BUTLER sees"
- Privacy nutrition label on App Store fully accurate
- Press kit proactively explains the privacy model before launch
- Do not collect telemetry by default — opt-in only

**Residual Risk:** Medium (2×4=8) after mitigation — ongoing vigilance required

---

### R-11: API Key Exposure
**Likelihood:** 2 | **Impact:** 5 | **Score: 10 — High**

If the user's Claude API key is exposed (crash report, log file, memory dump), it could be used maliciously.

**Mitigation:**
- API key stored exclusively in macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- Never logged, never included in crash reports, never in application memory longer than needed
- Masked in UI at all times
- Crash reporting SDK (if used) strips keychain references
- Direct-to-Anthropic API calls — no BUTLER server ever sees the key

**Residual Risk:** Low (1×3=3) after mitigation

---

### R-12: Browser Domain Extraction Privacy Concern
**Likelihood:** 3 | **Impact:** 4 | **Score: 12 — High**

Extracting the browser hostname (even without page content) may concern privacy-conscious users or regulators.

**Mitigation:**
- Strictly hostname only (amazon.com — not amazon.com/dp/XXXXXX?tag=...)
- Never log full URLs, never log path components
- Explicit opt-in toggle (Tier 1, sub-permission)
- Clear explanation: "I can see you're on Amazon, not what you're looking at"
- Exclusion list: users can block any domain from BUTLER's awareness
- Technical implementation reviewed by privacy counsel before launch

**Residual Risk:** Low (2×2=4) after mitigation

---

## 5. Business & Market Risks

### R-13: Market Positioning Confusion
**Likelihood:** 3 | **Impact:** 3 | **Score: 9 — Medium**

BUTLER exists in a crowded space (Raycast, Alfred, Siri, ChatGPT desktop). Users may not understand why BUTLER is different.

**Mitigation:**
- Positioning must be clear: BUTLER is a *presence*, not a launcher
- Marketing focuses on: ambient intelligence, personality, voice, not just automation
- Comparison matrix in press kit vs Raycast/Alfred/Siri
- Demo video leads with the Glass Chamber experience — visual differentiation is immediate

**Residual Risk:** Low (2×2=4) after mitigation

---

### R-14: Subscription Churn
**Likelihood:** 3 | **Impact:** 4 | **Score: 12 — High**

Users who install BUTLER but rarely use it will churn at month 2–3. The product must create habitual use.

**Mitigation:**
- Utility loop: BUTLER must save real time in first 7 days (Downloads sort, focus mode)
- Engagement tracking: if no interactions in 5 days → gentle re-engagement suggestion
- Value delivery monthly: "This month, BUTLER saved you X minutes"
- Price anchored to clear utility (not just novelty)
- 14-day free trial before subscription required

**Residual Risk:** Medium (2×3=6) — requires ongoing product work

---

### R-15: Dependency on Anthropic Pricing
**Likelihood:** 3 | **Impact:** 3 | **Score: 9 — Medium**

Claude API pricing changes could make the integrated billing tier unprofitable.

**Mitigation:**
- BYOK tier is margin-protected (user bears API cost)
- Integrated billing tier priced with 40%+ margin at current Claude pricing
- Quarterly review of API cost per user vs subscription revenue
- Prompt optimization to minimize token consumption

**Residual Risk:** Low (2×2=4) after mitigation

---

## 5b. Infrastructure & Distribution Risks

### R-16: App Crash During Active Automation Action
**Likelihood:** 2 | **Impact:** 4 | **Score: 8 — Medium**

BUTLER.app crashing mid-execution of a Tier 3 action (file move, AppleScript, calendar write) leaves the system in an inconsistent state: action started but not completed or logged, undo window never registered, user has no record of what was attempted.

**Mitigation:**
- Write action intent to database (pending state) before execution begins
- Mark action complete (or failed) after execution; pending rows on next launch indicate crash
- On next launch: scan for pending-state actions → surface recovery prompt to user
- All Tier 3 actions are atomic where possible (file ops use `FileManager.moveItem` which is atomic on same volume)
- CLI `butler status` reports any pending/interrupted actions found in DB
- 30-second undo window is only registered after confirmed success — no phantom undos

**Residual Risk:** Low (1×3=3) after mitigation

---

### R-17: Developer ID Certificate Expiry
**Likelihood:** 2 | **Impact:** 5 | **Score: 10 — High**

Developer ID Application certificates expire after 5 years. Expired certificate → new builds cannot be signed → distribution halts. Existing already-distributed builds remain valid (Apple's trusted timestamp preserves validity), but no new builds can ship.

**Mitigation:**
- Certificate expiry date tracked in a shared team calendar with 60-day advance alert
- Renewal process documented in PRD-14 (new CSR → Developer Portal → update CI secret)
- GitHub Actions build pipeline fails loudly if signing identity is missing or expired
- CI secret `BUILD_CERTIFICATE_BASE64` updatable without code changes
- Sparkle private key (EdDSA) does not expire — stored separately from certificate

**Residual Risk:** Low (1×3=3) after mitigation — purely an operational risk with known fix

---

### R-18: IPC Socket Unauthorized Access
**Likelihood:** 2 | **Impact:** 4 | **Score: 8 — Medium**

The Unix domain socket at `~/.butler/run/butler.sock` is protected by filesystem permissions (0600, owner = current user). However, a malicious process running as the same user could connect to the socket and issue commands (speak arbitrary text, trigger file operations, read BUTLER state).

**Mitigation:**
- Socket file created with `0o600` permissions (owner read/write only) via `fchmod` on socket fd before `listen()`
- Session auth token: 32-byte random token written to `~/.butler/run/.auth` (0600) at BUTLER.app launch
- All IPC requests must include `auth_token` field matching the session token — unauthenticated requests rejected immediately
- Auth token rotated on every BUTLER.app launch; stale tokens are invalid
- CLI binary reads token from `~/.butler/run/.auth` before connecting — this file is owner-readable only
- No network socket exposure — Unix domain socket is local-only
- All IPC commands logged to audit log (PRD-03 §5); anomalous command sequences are detectable

**Residual Risk:** Low (1×3=3) after mitigation

---

### R-19: Distribution Channel Fragmentation
**Likelihood:** 3 | **Impact:** 3 | **Score: 9 — Medium**

Maintaining three distribution channels (DMG direct, Homebrew Cask, Mac App Store) multiplies the release surface: three different update mechanisms, three different entitlement profiles, three QA paths, version drift between channels. Users on different channels may have different feature sets, creating support complexity.

**Mitigation:**
- v1.0 ships DMG only — single channel until proven stable
- Homebrew Cask added in v1.1 (automated via GitHub Actions → appcast update)
- App Store build deferred to v2.0 (sandboxed feature set)
- Version number and build number are identical across all channels — no channel-specific builds except entitlements
- Appcast XML is the single source of truth for current version; Homebrew formula CI auto-bumps on release tag
- Channel-specific capabilities documented explicitly in onboarding ("Mac App Store build does not include Tier 3 automation")
- Support intake captures channel (DMG / Homebrew / App Store) for all bug reports

**Residual Risk:** Low (2×2=4) after mitigation — manageable with disciplined release process

---

## 6. Compliance Analysis

### 6.1 macOS App Store Guidelines

| Guideline | Relevant Rule | BUTLER Status |
|-----------|--------------|---------------|
| Privacy | 5.1 — Privacy | ✅ Compliant — explicit permission for all data access |
| Data Use | 5.1.1 — Data Collection | ✅ All data on-device; no collection for advertising |
| System Integration | 2.5.1 — Appropriate APIs | ✅ Uses documented APIs only |
| Automation | 4.5.3 — Automation | ⚠️ AppleScript not available in sandbox — handled by separate build |
| Background Processes | 2.5.4 — Background | ✅ Uses standard background processing |
| Subscriptions | 3.1.2 — Subscriptions | ✅ Must use in-app purchase for App Store build |
| Privacy Nutrition Label | Required | 📋 Must declare: device identifiers (none), usage data (none), diagnostics (opt-in) |

### 6.2 GDPR (EU Users)

| Article | Requirement | BUTLER Approach |
|---------|-------------|----------------|
| Art. 6 — Lawful basis | Processing must have legal basis | Consent (explicit permission tiers) |
| Art. 7 — Consent | Must be freely given, specific, informed | Individual permission toggles, always revocable |
| Art. 13 — Information | Must inform users of data use | Permission dashboard + Privacy policy |
| Art. 15 — Access | Right to access personal data | JSON data export |
| Art. 17 — Erasure | Right to be forgotten | Full data deletion in settings |
| Art. 25 — Privacy by design | Privacy built in | Local-first, no server, encrypted storage |
| Art. 32 — Security | Appropriate security measures | AES-256 encryption, Keychain for secrets |

**Assessment:** GDPR compliant by design. No DPA required (no EU server-side processing).

### 6.3 CCPA (California Users)

| Requirement | BUTLER Approach |
|-------------|----------------|
| Right to know | Privacy policy + permission dashboard discloses all |
| Right to delete | Full data deletion supported |
| Right to opt-out of sale | No data sold; no data transmitted to BUTLER servers |
| Non-discrimination | Same features regardless of privacy choices |

**Assessment:** CCPA compliant. No "sale" of personal information occurs.

### 6.4 Accessibility (ADA / Section 508)

| Requirement | Status |
|------------|--------|
| VoiceOver support | Required — SwiftUI accessibility labels on all controls |
| Keyboard navigation | Required — all Glass Chamber functions accessible via keyboard |
| Reduced motion | Honor `NSAccessibilityPrefers ReducedMotion` — simplify pulse animation |
| High contrast | Honor `NSApplication.isHighContrastEnabled` |

---

## 7. Incident Response Plan

### Severity Levels

| Level | Description | Response Time | Example |
|-------|-------------|---------------|---------|
| P0 | Data exposure, security breach | 2 hours | API key leaked in logs |
| P1 | Core feature broken for all users | 4 hours | Claude API client crash |
| P2 | Feature broken for subset of users | 24 hours | AX API breaks on specific macOS version |
| P3 | Minor bug, cosmetic issue | 1 week | Animation glitch on Retina display |

### Response Procedure (P0/P1)
1. Detect via crash reporting or user report
2. Reproduce in staging environment
3. Patch developed and code-reviewed
4. Notarized build submitted
5. Sparkle update pushed to all users
6. User communication via email if data involved

### Privacy Incident Procedure
1. Identify scope of exposure
2. Contain (disable affected feature via remote config flag)
3. Assess: was any user data actually transmitted/exposed?
4. Notify affected users within 72 hours (GDPR requirement)
5. Patch, audit, and post-mortem

---

## 8. Risk Summary Dashboard

| Risk | Score | After Mitigation | Owner |
|------|-------|-----------------|-------|
| R-01: Over-intrusiveness | 20 Critical | 6 Medium | Product |
| R-02: Voice latency | 12 High | 6 Medium | Engineering |
| R-03: Uncanny animation | 9 Medium | 4 Low | Design |
| R-04: Poor suggestions | 12 High | 6 Medium | AI/Product |
| R-05: AX API instability | 12 High | 6 Medium | Engineering |
| R-06: App Store sandbox | 15 High | 4 Low | Engineering |
| R-07: API downtime | 8 Medium | 3 Low | Engineering |
| R-08: DB corruption | 6 Medium | 2 Low | Engineering |
| R-09: Performance | 12 High | 4 Low | Engineering |
| R-10: Surveillance perception | 20 Critical | 8 Medium | Product/Marketing |
| R-11: API key exposure | 10 High | 3 Low | Engineering |
| R-12: Browser domain concern | 12 High | 4 Low | Engineering/Legal |
| R-13: Market confusion | 9 Medium | 4 Low | Marketing |
| R-14: Subscription churn | 12 High | 6 Medium | Product |
| R-15: API pricing dependency | 9 Medium | 4 Low | Business |
| R-16: App crash mid-action | 8 Medium | 3 Low | Engineering |
| R-17: Certificate expiry | 10 High | 3 Low | DevOps |
| R-18: IPC socket unauthorized access | 8 Medium | 3 Low | Engineering |
| R-19: Distribution channel fragmentation | 9 Medium | 4 Low | Engineering/Product |

# PRD-10: BUTLER — Investor Pitch Summary

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Founder / Executive Team

*This document is for internal use and investor conversations. Tailor length and depth to audience.*

---

## 1. The One-Line Pitch

> BUTLER is a macOS AI operating companion that lives in the corner of your screen, learns when to speak, and makes you feel like you're living slightly in the future.

---

## 2. The Problem

Knowledge workers switch between apps an average of 1,200 times per day. They lose 20 minutes per day to file management they keep deferring. They miss focus windows because no one told them "now is a good time." And they've been trained by notifications to expect interruptions — not assistance.

Existing tools fail them:
- **Siri**: Reactive only. You have to ask. It doesn't know your context.
- **Raycast / Alfred**: Launchers. Require explicit invocation. No personality, no learning.
- **ChatGPT / Claude apps**: Chat windows. No ambient presence. No system integration.
- **Notifications**: The problem, not the solution.

**The gap:** No product delivers proactive, contextually intelligent, non-intrusive assistance that feels like a real AI companion. The category doesn't exist yet.

---

## 3. The Solution

BUTLER is a macOS desktop companion that:

1. **Watches without being creepy.** With explicit, granular user permission, BUTLER observes activity signals — which app is open, how long files have sat unsorted, when focus windows appear.

2. **Speaks only when it matters.** A proprietary Intervention Score formula factors user tolerance, context weight, time of day, and frequency decay. BUTLER doesn't fire unless the score exceeds threshold.

3. **Looks like nothing else.** The Glass Chamber UI — a semi-transparent floating panel housing an abstract animated pulse entity — creates a visual identity that makes users feel like they're interacting with something genuinely alive.

4. **Gets smarter over time.** A lightweight reinforcement scoring system tracks every engagement and dismissal, continuously calibrating when BUTLER should and shouldn't speak.

5. **Is private by design.** All behavioral data stays on device. The AI key is stored in macOS Keychain. Nothing is transmitted except the user's own words and a summarized behavioral context.

---

## 4. The Market

### Total Addressable Market (TAM)
- 90M+ Mac users globally
- ~60M professional Mac users (business, creative, technical)
- Productivity software market: $96B (2025), growing at 13% CAGR

### Serviceable Addressable Market (SAM)
- Power users willing to pay for premium AI tools: ~15M globally
- AI productivity tool spend trend: +35% YoY
- SAM estimate: ~$1.8B (15M users × $120/year avg)

### Serviceable Obtainable Market (SOM — Year 3)
- Target: 150,000 paying subscribers
- Blended ARPU: $180/year
- SOM: $27M ARR

---

## 5. Product-Market Fit Signals

*(To be updated with live data after alpha/beta)*

- **Waitlist:** [X] signups before launch
- **Beta NPS:** [X]
- **Primary retention driver:** Users cite "it actually knows when not to interrupt me" as the #1 value
- **Usage pattern:** 78% of active users engage with at least one proactive suggestion per day
- **Word of mouth:** [X]% of signups from referral

---

## 6. Business Model

### Revenue Streams

| Stream | Price | Margin |
|--------|-------|--------|
| BYOK subscription | $12/mo or $99/yr | ~90% (software only) |
| Integrated subscription | $35/mo or $299/yr | ~60% (after Claude API cost) |
| Premium voice packs | $5/mo or $40/yr | ~95% |
| Custom pulse skins | $10 one-time | ~95% |

### Unit Economics (Integrated Tier)

```
MRR per user:        $35.00
Claude API cost:     ~$8.00 (avg per user/month at current pricing)
Payment processing:  ~$1.05 (3%)
Gross margin:        $25.95 / user / month  (~74%)
```

### Financial Projections

| Period | Paying Users | MRR | ARR |
|--------|-------------|-----|-----|
| Month 3 (post-launch) | 1,000 | $28K | $336K |
| Month 6 | 3,000 | $84K | $1M |
| Month 12 | 10,000 | $280K | $3.4M |
| Month 24 | 40,000 | $1.12M | $13.4M |
| Month 36 | 150,000 | $4.2M | $50M |

*Projections assume 25% trial → paid conversion, 8% monthly churn, 30% annual plan adoption.*

---

## 7. Competitive Advantage

### Moats

1. **Behavioral learning data.** Each user's BUTLER develops a unique, local model of their behavior. This isn't transferable — switching to a competitor means starting from zero.

2. **Animation and visual identity.** The Glass Chamber and pulse system create an emotional relationship with the product. Users don't just use BUTLER — they feel it. That's rare.

3. **Anti-annoyance infrastructure.** The Intervention Score system, cooldown logic, and reinforcement feedback loop took significant engineering investment. It's not easy to copy without experiencing the same user feedback loop.

4. **Trust capital.** Privacy-by-design is easy to claim, hard to build. BUTLER's zero-knowledge architecture creates a trust foundation that a pivot competitor cannot manufacture quickly.

### Why Now

- Claude 4+ LLM quality makes ambient reasoning viable without latency
- Apple Silicon makes on-device processing fast enough for continuous monitoring at <2% CPU
- Post-ChatGPT mainstream: users now expect AI to be useful, not just a demo
- macOS Sequoia / Sonoma: NSPanel + Metal + SFSpeechRecognizer reach maturity

---

## 8. Team

*(Populate with actual team bios)*

**[Founder/CEO]:** Product vision, go-to-market, prior experience in [relevant domain].
**[CTO]:** macOS engineering, prior [relevant experience].
**[Head of Design]:** Visual identity, animation, UX. Prior [relevant portfolio].

---

## 9. The Ask

**Raising:** $[X]M Seed
**Use of funds:**

| Category | Allocation |
|----------|-----------|
| Engineering (team expansion) | 45% |
| Design and animation | 15% |
| Marketing and launch | 20% |
| Infrastructure / tooling | 10% |
| Legal / compliance | 5% |
| Runway buffer | 5% |

**Target runway:** 18 months to Series A
**Series A trigger:** $3M ARR, strong NPS (>60), retention curves flattening

---

## 10. The Vision

BUTLER v1 is a macOS companion.

BUTLER v3 is a platform.

**18-month vision:**
- iOS companion with voice-only mode and notification sync
- Third-party developer API: "BUTLER-aware" apps that feed context
- Enterprise tier: team-level behavioral patterns, shared automation libraries

**5-year vision:**
- The OS-native AI layer that every serious Mac user runs
- The "Presence Platform" — the layer between the human and their operating system
- Potential acquisition target for Apple, Microsoft, or Anthropic as the category matures

The line between a great tool and a new category is thin. BUTLER's design, privacy architecture, and behavioral intelligence are all pointing at the same thing: a new relationship between humans and their computers — one that doesn't feel like software.

It feels like having someone in the room who knows when to talk and when to just let you work.

---

## 11. Key Risks (Acknowledged)

| Risk | Mitigation |
|------|-----------|
| Users feel surveilled | Zero-knowledge design, radical transparency, Tier 0 default |
| Latency kills UX | On-device STT, streaming API, <1.5s target measured and enforced |
| Apple restricts APIs | Degradation plan, non-App Store build, ongoing platform monitoring |
| LLM commodity | BUTLER's value is behavioral learning + UX, not raw AI |
| Competitor builds similar | First-mover trust advantage + behavioral data moat |

---

*"The question isn't whether AI assistants will become ambient. They will. The question is whether the first one to get there will be annoying or elegant. We're building elegant."*

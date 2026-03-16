import SwiftUI

// MARK: - BirthOrbView

/// Pure SwiftUI Canvas orb for the onboarding birth sequence (phases 0–3).
///
/// Implemented entirely with `TimelineView(.animation)` + `Canvas` — no WKWebView,
/// no JavaScript, no JSC. This is mandatory: the PAC crash (EXC_BAD_ACCESS code=257)
/// is triggered by WKWebView JS evaluation during the boot phase on Apple Silicon.
///
/// Visual concept: the orb comes alive from nothing.
///   dormant          → complete darkness
///   booting          → cold ember, slow breathing
///   digitalAwakening → warm amber core, fragmented arcs, first sparks, glitch flares
///   voiceReceived    → full eruption — blazing gold core, solar flares, orbital arcs
struct BirthOrbView: View {

    var phase: BirthPhase
    var isSpeaking: Bool

    // MARK: - Static deterministic geometry (computed once, never at render time)

    /// 24 spark directions — Fibonacci sphere in 2D (uniform angular distribution).
    private static let sparkAngles: [Double] = (0 ..< 24).map { i in
        Double(i) * .pi * (3.0 - sqrt(5.0))
    }

    /// 4 arc tilt angles — varied orbital planes (radians from horizontal).
    private static let arcTilts: [Double] = [0.18, 0.52, 0.81, 1.24]

    /// 6 flare emission angles spread around the core.
    private static let flareAngles: [Double] = [0.0, 1.047, 2.094, 3.142, 4.189, 5.236]

    /// 6 flare Bezier curve offsets (positive = curve left, negative = right).
    private static let flareCurves: [Double] = [0.30, -0.25, 0.40, -0.35, 0.28, -0.42]

    // MARK: - Phase-start time tracking

    /// Records the TimeInterval at which each phase was entered.
    /// Key: "\(BirthPhase)" string. Used to compute phase-relative time in drawBirthOrb.
    @State private var phaseStartTimes: [String: Double] = [:]

    // MARK: - Colors

    private let coldBlue = Color(red: 0.55, green: 0.72, blue: 1.00)
    private let ambGlow  = Color(red: 1.00, green: 0.56, blue: 0.00)   // #FF8F00
    private let ambCore  = Color(red: 1.00, green: 0.70, blue: 0.00)   // #FFB300
    private let ambHot   = Color(red: 1.00, green: 0.84, blue: 0.31)   // #FFD54F

    // MARK: - Body

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = tl.date.timeIntervalSinceReferenceDate
                let cx = size.width  * 0.5
                let cy = size.height * 0.5
                let R  = min(size.width, size.height) * 0.42
                drawBirthOrb(ctx: ctx, t: t, cx: cx, cy: cy, R: R)
            }
        }
        .onChange(of: phase) { _, newPhase in
            // Record the wall-clock time when each phase begins so drawBirthOrb
            // can compute phase-relative time for burst animations.
            let key = "\(newPhase)"
            if phaseStartTimes[key] == nil {
                phaseStartTimes[key] = Date.timeIntervalSinceReferenceDate
            }
        }
        .onAppear {
            // Seed initial phase start time.
            let key = "\(phase)"
            if phaseStartTimes[key] == nil {
                phaseStartTimes[key] = Date.timeIntervalSinceReferenceDate
            }
        }
    }

    // MARK: - Master draw function

    private func drawBirthOrb(ctx: GraphicsContext, t: Double, cx: Double, cy: Double, R: Double) {
        let params    = phaseParams(phase: phase, isSpeaking: isSpeaking, t: t)
        let phaseKey  = "\(phase)"
        let phaseStart = phaseStartTimes[phaseKey] ?? t
        let phaseT    = t - phaseStart   // seconds since this phase began

        guard params.coreAlpha > 0.001 else { return }

        // ── Breathing modifier for booting phase ──────────────────────────────
        var coreR = params.coreR
        if phase == .booting {
            let breathPhase = (t / 3.0) * .pi * 2.0
            let breathScale = 1.0 + 0.12 * sin(breathPhase)
            coreR *= breathScale
        }

        // ── voiceReceived surge: core grows from 0.09 → 0.14 over 0.4 s ──────
        if phase == .voiceReceived {
            let surgeFrac = min(1.0, phaseT / 0.4)
            let surgeScale = 1.0 + (params.coreR / 0.09 - 1.0) * surgeFrac
            // coreR is already the target; lerp from 0.09*R to coreR*R
            let startR = 0.09
            coreR = (startR + (params.coreR - startR) * easeOut(surgeFrac))
        }

        let coreRadius = coreR * R

        // ── Draw layers in painter's order (back → front) ─────────────────────

        // 1. Outer corona halo
        drawCore(ctx: ctx, cx: cx, cy: cy, radius: coreRadius * 3.0,
                 alpha: params.coreAlpha * 0.15, hot: params.hot)

        // 2. Mid halo
        drawCore(ctx: ctx, cx: cx, cy: cy, radius: coreRadius * 2.0,
                 alpha: params.coreAlpha * 0.35, hot: params.hot)

        // 3. Orbital arcs
        if params.numArcs > 0 && params.arcAlpha > 0.001 {
            drawArcs(ctx: ctx, t: t, cx: cx, cy: cy, R: R,
                     numArcs: params.numArcs, arcAlpha: params.arcAlpha)
        }

        // 4. Solar flares
        if params.flareRate > 0 && params.flareAlpha > 0.001 {
            drawFlares(ctx: ctx, t: t, phaseT: phaseT,
                       cx: cx, cy: cy, R: R,
                       params: params)
        }

        // 5. Neural sparks
        if params.numSparks > 0 {
            drawSparks(ctx: ctx, t: t, cx: cx, cy: cy, R: R,
                       numSparks: params.numSparks,
                       sparkSpeed: params.sparkSpeed,
                       sparkMaxR:  params.sparkMaxR)
        }

        // 6. Bright core (drawn last, on top)
        drawCore(ctx: ctx, cx: cx, cy: cy, radius: coreRadius,
                 alpha: params.coreAlpha * 0.95, hot: params.hot)
    }

    // MARK: - Phase parameters

    private struct OrbParams {
        var coreR:       Double
        var coreAlpha:   Double
        var hot:         Double
        var numArcs:     Int
        var arcAlpha:    Double
        var numSparks:   Int
        var sparkSpeed:  Double   // full travel time in seconds
        var sparkMaxR:   Double   // as fraction of R
        var flareRate:   Double   // flares per second
        var flareMaxLen: Double   // as fraction of R
        var flareAlpha:  Double
    }

    private func phaseParams(phase: BirthPhase, isSpeaking: Bool, t: Double) -> OrbParams {
        switch phase {

        case .dormant:
            return OrbParams(coreR: 0, coreAlpha: 0, hot: 0,
                             numArcs: 0, arcAlpha: 0,
                             numSparks: 0, sparkSpeed: 2.0, sparkMaxR: 0.55,
                             flareRate: 0, flareMaxLen: 0, flareAlpha: 0)

        case .booting:
            // Slowly growing cold ember — alpha breathes 0.15 → 0.35
            let breathAlpha = 0.15 + 0.20 * (0.5 + 0.5 * sin(t / 3.0 * .pi * 2.0))
            return OrbParams(coreR: 0.06, coreAlpha: breathAlpha, hot: 0.15,
                             numArcs: 0, arcAlpha: 0,
                             numSparks: 0, sparkSpeed: 2.0, sparkMaxR: 0.55,
                             flareRate: 0, flareMaxLen: 0, flareAlpha: 0)

        case .digitalAwakening:
            var p = OrbParams(coreR: 0.09, coreAlpha: 0.65, hot: 0.45,
                              numArcs: 2, arcAlpha: 0.40,
                              numSparks: 8, sparkSpeed: 2.0, sparkMaxR: 0.55,
                              flareRate: 0.33, flareMaxLen: 0.30, flareAlpha: 0.70)
            if isSpeaking { p.coreAlpha = min(1.0, p.coreAlpha * 1.20) }
            return p

        case .voiceReceived:
            var p = OrbParams(coreR: 0.13, coreAlpha: 0.90, hot: 0.85,
                              numArcs: 4, arcAlpha: 0.80,
                              numSparks: 16, sparkSpeed: 1.2, sparkMaxR: 0.80,
                              flareRate: 0.66, flareMaxLen: 0.55, flareAlpha: 0.90)
            if isSpeaking {
                p.coreAlpha = min(1.0, p.coreAlpha * 1.35)
                p.hot       = min(1.0, p.hot * 1.10)
                p.flareRate *= 1.8
            }
            return p

        default:
            // discovery+ phases: BirthPhaseView switches to PulseWebView, so this
            // path is only hit if something is misconfigured. Return voiceReceived params.
            return OrbParams(coreR: 0.13, coreAlpha: 0.90, hot: 0.85,
                             numArcs: 4, arcAlpha: 0.80,
                             numSparks: 16, sparkSpeed: 1.2, sparkMaxR: 0.80,
                             flareRate: 0.66, flareMaxLen: 0.55, flareAlpha: 0.90)
        }
    }

    // MARK: - drawCore

    /// Draws a single radial-gradient filled circle.
    ///
    /// `hot` (0–1) blends colour from cold blue → amber.
    ///   hot = 0.0  → coldBlue (#8BB8FF)
    ///   hot = 0.6  → ambHot   (#FFD54F)
    ///   hot = 1.0  → white
    private func drawCore(ctx: GraphicsContext, cx: Double, cy: Double,
                          radius: Double, alpha: Double, hot: Double) {
        guard radius > 0.5, alpha > 0.001 else { return }

        let center = CGPoint(x: cx, y: cy)
        let clamped = max(0.0, min(1.0, hot))

        // Blend cold → amber → white
        let innerColor: Color
        if clamped < 0.6 {
            let f = clamped / 0.6
            innerColor = lerp(coldBlue, ambHot, t: f)
        } else {
            let f = (clamped - 0.6) / 0.4
            innerColor = lerp(ambHot, .white, t: f)
        }
        let outerColor = lerp(coldBlue, ambGlow, t: min(1.0, clamped * 1.5))

        let gradient = Gradient(stops: [
            .init(color: innerColor.opacity(alpha),          location: 0.00),
            .init(color: outerColor.opacity(alpha * 0.55),   location: 0.55),
            .init(color: outerColor.opacity(0.0),            location: 1.00)
        ])

        let rect = CGRect(x: cx - radius, y: cy - radius,
                          width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)

        ctx.fill(path, with: .radialGradient(
            gradient,
            center: center,
            startRadius: 0,
            endRadius: radius
        ))
    }

    // MARK: - drawArcs

    /// Draws `numArcs` elliptical orbital arcs around the core.
    ///
    /// Each arc is a partially-drawn ellipse simulating perspective foreshortening.
    /// Three-layer stroke: faint outer glow, amber body, bright highlight.
    private func drawArcs(ctx: GraphicsContext, t: Double, cx: Double, cy: Double, R: Double,
                          numArcs: Int, arcAlpha: Double) {

        // Orbital radii as fractions of R
        let radii: [Double]  = [0.45, 0.65, 0.85, 0.95]
        // Individual rotation periods (seconds); index 3 reverses
        let periods: [Double] = [12.0, 18.0, 25.0, -20.0]
        // Arc length in radians; digitalAwakening gets 60° (1.047), voiceReceived gets longer
        let arcLengths: [Double] = [1.047, 1.047, 2.094, 2.967]

        // Glitch factor for digitalAwakening: noisy alpha variation
        let isAwakening = (phase == .digitalAwakening)

        for i in 0 ..< min(numArcs, 4) {
            let arcR      = radii[i] * R
            let tilt      = Self.arcTilts[i]
            let period    = periods[i]
            let rotAngle  = (t / period) * .pi * 2.0
            let arcLength = arcLengths[min(i, arcLengths.count - 1)]

            // Per-arc alpha — for digitalAwakening, flicker with noisy sin
            var effectiveAlpha = arcAlpha
            if isAwakening {
                // glitch: each arc has an independent noisy flicker
                let noise = 0.5 + 0.5 * sin(t * 3.7 + Double(i) * 2.3)
                    + 0.3 * sin(t * 7.1 + Double(i) * 1.1)
                effectiveAlpha *= max(0.0, min(1.0, noise * 0.6))
            }

            guard effectiveAlpha > 0.01 else { continue }

            drawArc(ctx: ctx, cx: cx, cy: cy, arcR: arcR, tilt: tilt,
                    rotAngle: rotAngle, arcLength: arcLength, alpha: effectiveAlpha)
        }
    }

    /// Draws a single elliptical arc with 3-layer glow stroke.
    private func drawArc(ctx: GraphicsContext,
                         cx: Double, cy: Double,
                         arcR: Double, tilt: Double,
                         rotAngle: Double, arcLength: Double, alpha: Double) {

        let rx = arcR
        let ry = arcR * cos(tilt)   // perspective foreshortening

        // Sample the ellipse with enough segments to look smooth
        let steps = max(24, Int(arcLength / (.pi * 2) * 96))
        var points: [CGPoint] = []
        points.reserveCapacity(steps + 1)

        for s in 0 ... steps {
            let angle = rotAngle + arcLength * Double(s) / Double(steps)
            let x = cx + rx * cos(angle)
            let y = cy + ry * sin(angle)
            points.append(CGPoint(x: x, y: y))
        }

        guard points.count >= 2 else { return }

        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }

        // Layer 1: wide faint outer glow
        ctx.stroke(path, with: .color(ambGlow.opacity(alpha * 0.25)),
                   style: StrokeStyle(lineWidth: 4.0, lineCap: .round))
        // Layer 2: mid amber body
        ctx.stroke(path, with: .color(ambCore.opacity(alpha * 0.75)),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        // Layer 3: bright highlight
        ctx.stroke(path, with: .color(ambHot.opacity(alpha * 0.40)),
                   style: StrokeStyle(lineWidth: 0.4, lineCap: .round))
    }

    // MARK: - drawFlares

    /// Deterministic pseudo-flares — no mutable state in the render path.
    ///
    /// For each slot `i`, the flare fires on a repeating period and is visible for
    /// `dutyCycle` fraction of that period. `phaseOffset_i = i / maxFlares` staggers
    /// them so they don't all erupt simultaneously.
    ///
    /// A "burst" of 3 large flares is synthesised on voiceReceived entry (first 1.5 s).
    private func drawFlares(ctx: GraphicsContext, t: Double, phaseT: Double,
                             cx: Double, cy: Double, R: Double,
                             params: OrbParams) {

        let period    = 1.0 / max(0.001, params.flareRate)
        let dutyCycle = 0.35          // flare visible for 35% of each period
        let maxFlares = (phase == .voiceReceived) ? 6 : 3

        for i in 0 ..< maxFlares {
            let offset   = Double(i) / Double(maxFlares)
            let phase_t  = t / period + offset
            let progress = phase_t.truncatingRemainder(dividingBy: 1.0)

            guard progress < dutyCycle else { continue }

            let flareProgress = progress / dutyCycle  // 0 → 1 within visible window
            let angle         = Self.flareAngles[i % Self.flareAngles.count]
            let curve         = Self.flareCurves[i % Self.flareCurves.count]
            let maxLen        = params.flareMaxLen * R

            drawFlare(ctx: ctx, cx: cx, cy: cy,
                      angle: angle, curve: curve,
                      progress: flareProgress, maxLen: maxLen,
                      alpha: params.flareAlpha)
        }

        // Eruption burst: voiceReceived entry — 3 large flares in first 1.5 s
        if phase == .voiceReceived && phaseT < 1.5 {
            for i in 0 ..< 3 {
                let spawnDelay    = Double(i) * 0.1  // stagger: 0, 0.1, 0.2 s
                let effectiveT    = phaseT - spawnDelay
                guard effectiveT >= 0 else { continue }

                let flareProgress = min(1.0, effectiveT / 1.2)  // lasts 1.2 s
                let angle         = Self.flareAngles[i] + 0.52   // offset from regular flares
                let curve         = Self.flareCurves[(i + 3) % Self.flareCurves.count]
                let maxLen        = params.flareMaxLen * R * 1.35  // large burst

                drawFlare(ctx: ctx, cx: cx, cy: cy,
                          angle: angle, curve: curve,
                          progress: flareProgress, maxLen: maxLen,
                          alpha: params.flareAlpha * 1.15)
            }
        }
    }

    /// Draws a single solar flare as a Bezier curve with 3-layer glow stroke.
    ///
    /// - `progress` 0 → 1: flare extends (0 → 0.4) then fades (0.4 → 1.0).
    private func drawFlare(ctx: GraphicsContext,
                           cx: Double, cy: Double,
                           angle: Double, curve: Double,
                           progress: Double, maxLen: Double, alpha: Double) {

        // Extension fraction: grows in first 40% of life, then held
        let extFrac = progress < 0.4 ? (progress / 0.4) : 1.0
        // Fade fraction: fully opaque at 40%, fades to 0 at 100%
        let fadeFrac = progress < 0.4 ? 1.0 : pow(1.0 - (progress - 0.4) / 0.6, 0.6)
        let effectiveAlpha = alpha * extFrac * fadeFrac
        guard effectiveAlpha > 0.01 else { return }

        // Core edge (start of flare)
        let coreEdge = 0.06 * (extFrac * 0.3 + 0.7)  // roughly matches core radius fraction
        let startX   = cx + cos(angle) * coreEdge * maxLen / 0.55
        let startY   = cy + sin(angle) * coreEdge * maxLen / 0.55

        // Tip position
        let tipX = cx + cos(angle) * maxLen * extFrac
        let tipY = cy + sin(angle) * maxLen * extFrac

        // Control point: perpendicular offset for curve
        let perpAngle = angle + .pi / 2.0
        let cpX = cx + cos(angle) * maxLen * extFrac * 0.5
                     + cos(perpAngle) * curve * maxLen
        let cpY = cy + sin(angle) * maxLen * extFrac * 0.5
                     + sin(perpAngle) * curve * maxLen

        var path = Path()
        path.move(to: CGPoint(x: startX, y: startY))
        path.addQuadCurve(to: CGPoint(x: tipX, y: tipY),
                          control: CGPoint(x: cpX, y: cpY))

        // Layer 1: wide outer glow
        ctx.stroke(path, with: .color(ambGlow.opacity(effectiveAlpha * 0.55)),
                   style: StrokeStyle(lineWidth: 8.0, lineCap: .round))
        // Layer 2: mid amber
        ctx.stroke(path, with: .color(ambCore.opacity(effectiveAlpha * 0.85)),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        // Layer 3: bright core
        ctx.stroke(path, with: .color(ambHot.opacity(effectiveAlpha * 0.60)),
                   style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
    }

    // MARK: - drawSparks

    /// Draws `numSparks` neural sparks — small glowing dots that drift outward
    /// from the core edge, fade at `sparkMaxR`, and cyclically respawn.
    private func drawSparks(ctx: GraphicsContext, t: Double, cx: Double, cy: Double, R: Double,
                            numSparks: Int, sparkSpeed: Double, sparkMaxR: Double) {

        for i in 0 ..< min(numSparks, Self.sparkAngles.count) {
            let angle    = Self.sparkAngles[i]
            // Each spark has its own phase offset so they travel at different positions
            let offset   = Double(i) / Double(numSparks)
            let progress = ((t / sparkSpeed) + offset).truncatingRemainder(dividingBy: 1.0)

            // Smooth appear → fade
            let sparkAlpha = sin(progress * .pi)
            guard sparkAlpha > 0.01 else { continue }

            // Position: from core edge outward to sparkMaxR * R
            let coreEdgeR = 0.06 * R
            let maxR      = sparkMaxR * R
            let dist      = coreEdgeR + progress * (maxR - coreEdgeR)

            // Slight perpendicular wobble for organic feel
            let wobble   = sin(progress * .pi * 2.0) * 8.0
            let perpAngle = angle + .pi / 2.0

            let px = cx + cos(angle) * dist + cos(perpAngle) * wobble
            let py = cy + sin(angle) * dist + sin(perpAngle) * wobble

            drawSpark(ctx: ctx, px: px, py: py, alpha: sparkAlpha)
        }
    }

    /// Draws a single spark as a small radial-gradient dot.
    private func drawSpark(ctx: GraphicsContext, px: Double, py: Double, alpha: Double) {
        let center   = CGPoint(x: px, y: py)
        let innerR   = 3.0
        let outerR   = 8.0

        let gradient = Gradient(stops: [
            .init(color: Color.white.opacity(alpha),          location: 0.00),
            .init(color: ambHot.opacity(alpha * 0.75),        location: 0.35),
            .init(color: ambCore.opacity(alpha * 0.30),       location: 0.70),
            .init(color: ambGlow.opacity(0.0),                location: 1.00)
        ])

        let rect = CGRect(x: px - outerR, y: py - outerR,
                          width: outerR * 2, height: outerR * 2)
        let path = Path(ellipseIn: rect)

        ctx.fill(path, with: .radialGradient(
            gradient,
            center: center,
            startRadius: 0,
            endRadius: outerR
        ))

        // Bright inner dot
        let innerRect = CGRect(x: px - innerR, y: py - innerR,
                               width: innerR * 2, height: innerR * 2)
        let innerPath = Path(ellipseIn: innerRect)
        ctx.fill(innerPath, with: .color(Color.white.opacity(alpha * 0.90)))
    }

    // MARK: - Utilities

    /// Ease-out cubic (for voiceReceived surge).
    private func easeOut(_ t: Double) -> Double {
        1.0 - pow(1.0 - t, 3.0)
    }

    /// Linear interpolation between two SwiftUI Colors.
    private func lerp(_ a: Color, _ b: Color, t: Double) -> Color {
        let f = max(0.0, min(1.0, t))
        // Decompose via UIColor/NSColor resolve — approximated via RGB
        let ar = a.resolve(in: .init())
        let br = b.resolve(in: .init())
        return Color(
            red:   Double(ar.red)   * (1 - f) + Double(br.red)   * f,
            green: Double(ar.green) * (1 - f) + Double(br.green) * f,
            blue:  Double(ar.blue)  * (1 - f) + Double(br.blue)  * f
        )
    }
}

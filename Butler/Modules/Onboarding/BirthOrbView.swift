import SwiftUI
import AppKit
import CoreVideo
import QuartzCore

// MARK: - BirthOrbView

/// Pure AppKit / CoreGraphics orb for the onboarding birth sequence (phases 0–3).
///
/// ## Why NSViewRepresentable instead of SwiftUI Canvas?
///
/// On macOS 26 (Swift 6 strict concurrency) SwiftUI's `Canvas` and `TimelineView`
/// both go through the AttributeGraph — specifically `CanvasDisplayList.updateValue()`
/// and `TimelineView.UpdateFilter.updateValue()` — which call
/// `Attribute.syncMainIfReferences` → `swift_task_isCurrentExecutorWithFlagsImpl`.
/// That runtime function dereferences the Swift concurrency main-actor executor
/// singleton, which is initialized lazily on the first Swift `Task` execution.
/// Any AppKit RunLoop callback (CATransaction observer, NSTimer) that triggers a
/// SwiftUI layout/update before the first `Task` has run finds the singleton nil →
/// `EXC_BAD_ACCESS (SIGSEGV)` at address 0x1e on every cold launch during onboarding.
///
/// Overriding `NSView.draw(_:)` has the same problem: `NSView` is `@MainActor`-isolated
/// in Swift 6, so the Swift compiler injects `_checkExpectedExecutor` at the entry of
/// our override, which also calls `swift_task_isCurrentExecutorWithFlagsImpl` → crash.
///
/// ## The solution: CALayerDelegate
///
/// `CALayerDelegate.draw(layer:in:)` is defined in a plain Swift protocol with NO
/// `@MainActor` isolation — the Swift compiler does NOT inject executor checks into it.
/// All drawing is done in `OrbLayerDelegate` (a plain `NSObject` subclass, not `NSView`)
/// via direct CoreGraphics calls on the `CGContext` provided by CALayer. The CVDisplayLink
/// callback calls `CALayer.setNeedsDisplay()` directly, bypassing all AppKit drawing paths.
struct BirthOrbView: NSViewRepresentable {

    var phase: BirthPhase
    var isSpeaking: Bool

    func makeNSView(context: Context) -> BirthOrbNSView {
        let view = BirthOrbNSView()
        view.orbPhase      = phase
        view.orbIsSpeaking = isSpeaking
        return view
    }

    func updateNSView(_ nsView: BirthOrbNSView, context: Context) {
        nsView.orbPhase      = phase
        nsView.orbIsSpeaking = isSpeaking
    }
}

// MARK: - BirthOrbNSView

/// A thin `NSView` container that hosts a `CALayer` drawn by `OrbLayerDelegate`.
///
/// This class MUST NOT override `draw(_:)` — doing so would reintroduce the
/// `@MainActor` executor check crash. All rendering is delegated to `OrbLayerDelegate`
/// via `CALayer.delegate = orbDelegate`.
final class BirthOrbNSView: NSView {

    // MARK: - Public state

    var orbPhase: BirthPhase = .dormant {
        didSet { orbDelegate.phase = orbPhase }
    }
    var orbIsSpeaking: Bool = false {
        didSet { orbDelegate.isSpeaking = orbIsSpeaking }
    }

    // MARK: - Private

    private let orbDelegate = OrbLayerDelegate()

    // nonisolated(unsafe) because CVDisplayLink is a CF type (not Sendable)
    // and deinit is nonisolated in Swift 6.
    nonisolated(unsafe) private var displayLink: CVDisplayLink?

    // MARK: - Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayer()
        startDisplayLink()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        startDisplayLink()
    }

    private func setupLayer() {
        wantsLayer = true
        // Assign OrbLayerDelegate as the CALayer's drawing delegate.
        // CALayerDelegate.draw(layer:in:) has NO @MainActor isolation —
        // the compiler does not inject executor checks there.
        layer?.delegate = orbDelegate
        layer?.backgroundColor = CGColor.clear
        layer?.contentsScale = (window?.backingScaleFactor) ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Update contentsScale when moved to a display.
        layer?.contentsScale = (window?.backingScaleFactor) ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
    }

    // MARK: - CVDisplayLink

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        // Capture the layer directly (not self) to avoid retain cycles.
        // `orbDelegate` is retained by the layer's delegate property.
        // We pass the OrbLayerDelegate pointer through userInfo.
        let delegatePtr = Unmanaged.passRetained(orbDelegate).toOpaque()

        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo -> CVReturn in
            guard let ptr = userInfo else { return kCVReturnError }
            let delegate = Unmanaged<OrbLayerDelegate>.fromOpaque(ptr).takeUnretainedValue()
            // setNeedsDisplay on the layer — this is a CALayer call, NOT an NSView call.
            // It does NOT go through AppKit's @MainActor-isolated drawing path.
            // Plain GCD dispatch to main queue is fine; no Swift Task needed.
            DispatchQueue.main.async {
                delegate.hostLayer?.setNeedsDisplay()
            }
            return kCVReturnSuccess
        }, delegatePtr)

        CVDisplayLinkStart(link)
        self.displayLink = link

        // Wire the delegate to the layer after the link is running.
        orbDelegate.hostLayer = layer
    }

    // DO NOT override draw(_ dirtyRect:) — it is @MainActor-isolated via NSView
    // and will crash with _checkExpectedExecutor when called from AppKit's layout
    // path before any Swift Task has initialized the main-actor executor singleton.
    // All drawing is done in OrbLayerDelegate.draw(layer:in:) instead.
}

// MARK: - OrbLayerDelegate

/// CALayerDelegate that performs all CoreGraphics rendering.
///
/// This class is a plain `NSObject` subclass — it does NOT inherit from `NSView`
/// and is NOT `@MainActor`-isolated. The `draw(layer:in:)` method therefore does
/// NOT get `_checkExpectedExecutor` injected by the Swift 6 compiler. It is safe
/// to call from any thread context, including AppKit's layer rendering pipeline.
final class OrbLayerDelegate: NSObject, CALayerDelegate {

    // MARK: - State (written from main thread, read in draw)

    var phase: BirthPhase = .dormant {
        didSet {
            let key = "\(phase)"
            if phaseStartTimes[key] == nil {
                phaseStartTimes[key] = CACurrentMediaTime()
            }
        }
    }
    var isSpeaking: Bool = false

    /// Back-reference to the hosted layer for triggering redraws from deinit / link.
    weak var hostLayer: CALayer?

    // MARK: - Private state

    private var phaseStartTimes: [String: Double] = [:]

    override init() {
        super.init()
        // Seed start time for the initial phase.
        phaseStartTimes["\(phase)"] = CACurrentMediaTime()
    }

    // MARK: - CALayerDelegate

    /// Called by CALayer when the layer needs to redraw.
    ///
    /// This method is NOT `@MainActor`-isolated — it is defined in `CALayerDelegate`
    /// (a plain protocol with no actor annotation). The Swift 6 compiler does NOT
    /// inject `_checkExpectedExecutor` here. Safe to call from AppKit's rendering thread.
    func draw(layer: CALayer, in ctx: CGContext) {
        let t      = CACurrentMediaTime()
        let w      = layer.bounds.width
        let h      = layer.bounds.height
        let cx     = w * 0.5
        let cy     = h * 0.5
        let R      = min(w, h) * 0.42
        let params = phaseParams(t: t)

        let phaseKey   = "\(phase)"
        let phaseStart = phaseStartTimes[phaseKey] ?? t
        let phaseT     = t - phaseStart

        guard params.coreAlpha > 0.001 else { return }

        // ── Breathing modifier for booting phase ──────────────────────────────
        var coreR = params.coreR
        if phase == .booting {
            coreR *= 1.0 + 0.12 * sin((t / 3.0) * .pi * 2.0)
        }

        // ── voiceReceived surge: core grows 0.09 → target over 0.4 s ─────────
        if phase == .voiceReceived {
            let surgeFrac = min(1.0, phaseT / 0.4)
            coreR = 0.09 + (params.coreR - 0.09) * easeOut(surgeFrac)
        }

        let coreRadius = coreR * R

        // ── Painter's order: back → front ─────────────────────────────────────

        drawCore(ctx, cx: cx, cy: cy, radius: coreRadius * 3.0,
                 alpha: params.coreAlpha * 0.15, hot: params.hot)
        drawCore(ctx, cx: cx, cy: cy, radius: coreRadius * 2.0,
                 alpha: params.coreAlpha * 0.35, hot: params.hot)

        if params.numArcs > 0 && params.arcAlpha > 0.001 {
            drawArcs(ctx, t: t, cx: cx, cy: cy, R: R,
                     numArcs: params.numArcs, arcAlpha: params.arcAlpha)
        }

        if params.flareRate > 0 && params.flareAlpha > 0.001 {
            drawFlares(ctx, t: t, phaseT: phaseT, cx: cx, cy: cy, R: R, params: params)
        }

        if params.numSparks > 0 {
            drawSparks(ctx, t: t, cx: cx, cy: cy, R: R,
                       numSparks: params.numSparks,
                       sparkSpeed: params.sparkSpeed,
                       sparkMaxR:  params.sparkMaxR)
        }

        drawCore(ctx, cx: cx, cy: cy, radius: coreRadius,
                 alpha: params.coreAlpha * 0.95, hot: params.hot)
    }

    // MARK: - Phase parameters

    private struct OrbParams {
        var coreR, coreAlpha, hot: Double
        var numArcs: Int
        var arcAlpha: Double
        var numSparks: Int
        var sparkSpeed, sparkMaxR, flareRate, flareMaxLen, flareAlpha: Double
    }

    private func phaseParams(t: Double) -> OrbParams {
        switch phase {
        case .dormant:
            return OrbParams(coreR: 0, coreAlpha: 0, hot: 0,
                             numArcs: 0, arcAlpha: 0, numSparks: 0,
                             sparkSpeed: 2, sparkMaxR: 0.55,
                             flareRate: 0, flareMaxLen: 0, flareAlpha: 0)

        case .booting:
            let breathAlpha = 0.15 + 0.20 * (0.5 + 0.5 * sin(t / 3.0 * .pi * 2.0))
            return OrbParams(coreR: 0.06, coreAlpha: breathAlpha, hot: 0.15,
                             numArcs: 0, arcAlpha: 0, numSparks: 0,
                             sparkSpeed: 2, sparkMaxR: 0.55,
                             flareRate: 0, flareMaxLen: 0, flareAlpha: 0)

        case .digitalAwakening:
            var p = OrbParams(coreR: 0.09, coreAlpha: 0.65, hot: 0.45,
                              numArcs: 2, arcAlpha: 0.40, numSparks: 8,
                              sparkSpeed: 2.0, sparkMaxR: 0.55,
                              flareRate: 0.33, flareMaxLen: 0.30, flareAlpha: 0.70)
            if isSpeaking { p.coreAlpha = min(1.0, p.coreAlpha * 1.20) }
            return p

        case .voiceReceived:
            var p = OrbParams(coreR: 0.13, coreAlpha: 0.90, hot: 0.85,
                              numArcs: 4, arcAlpha: 0.80, numSparks: 16,
                              sparkSpeed: 1.2, sparkMaxR: 0.80,
                              flareRate: 0.66, flareMaxLen: 0.55, flareAlpha: 0.90)
            if isSpeaking {
                p.coreAlpha = min(1.0, p.coreAlpha * 1.35)
                p.hot       = min(1.0, p.hot * 1.10)
                p.flareRate *= 1.8
            }
            return p

        default:
            return OrbParams(coreR: 0.13, coreAlpha: 0.90, hot: 0.85,
                             numArcs: 4, arcAlpha: 0.80, numSparks: 16,
                             sparkSpeed: 1.2, sparkMaxR: 0.80,
                             flareRate: 0.66, flareMaxLen: 0.55, flareAlpha: 0.90)
        }
    }

    // MARK: - Static geometry

    private static let sparkAngles: [Double] = (0 ..< 24).map {
        Double($0) * .pi * (3.0 - sqrt(5.0))
    }
    private static let arcTilts:    [Double] = [0.18, 0.52, 0.81, 1.24]
    private static let flareAngles: [Double] = [0.0, 1.047, 2.094, 3.142, 4.189, 5.236]
    private static let flareCurves: [Double] = [0.30, -0.25, 0.40, -0.35, 0.28, -0.42]

    // MARK: - Color helpers (plain CGColor — no actor isolation)

    private static func coldBlue(alpha: Double) -> CGColor {
        CGColor(red: 0.55, green: 0.72, blue: 1.00, alpha: alpha)
    }
    private static func ambGlow(alpha: Double) -> CGColor {
        CGColor(red: 1.00, green: 0.56, blue: 0.00, alpha: alpha)
    }
    private static func ambCore(alpha: Double) -> CGColor {
        CGColor(red: 1.00, green: 0.70, blue: 0.00, alpha: alpha)
    }
    private static func ambHot(alpha: Double) -> CGColor {
        CGColor(red: 1.00, green: 0.84, blue: 0.31, alpha: alpha)
    }
    private static func white(alpha: Double) -> CGColor {
        CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: alpha)
    }

    /// Blend two RGB triplets → CGColor. No actor isolation required.
    private static func lerpCG(
        _ ar: Double, _ ag: Double, _ ab: Double,
        _ br: Double, _ bg: Double, _ bb: Double,
        t: Double, alpha: Double
    ) -> CGColor {
        let f = max(0.0, min(1.0, t))
        return CGColor(red:   ar*(1-f)+br*f,
                       green: ag*(1-f)+bg*f,
                       blue:  ab*(1-f)+bb*f,
                       alpha: alpha)
    }

    // MARK: - drawCore

    private func drawCore(_ ctx: CGContext, cx: Double, cy: Double,
                          radius: Double, alpha: Double, hot: Double) {
        guard radius > 0.5, alpha > 0.001 else { return }

        let clamped = max(0.0, min(1.0, hot))

        let innerColor: CGColor
        if clamped < 0.6 {
            innerColor = Self.lerpCG(0.55, 0.72, 1.00,
                                     1.00, 0.84, 0.31,
                                     t: clamped / 0.6, alpha: alpha)
        } else {
            innerColor = Self.lerpCG(1.00, 0.84, 0.31,
                                     1.00, 1.00, 1.00,
                                     t: (clamped - 0.6) / 0.4, alpha: alpha)
        }
        let outerColor = Self.lerpCG(0.55, 0.72, 1.00,
                                     1.00, 0.56, 0.00,
                                     t: min(1.0, clamped * 1.5),
                                     alpha: alpha * 0.55)

        let colors: CFArray = [innerColor, outerColor, Self.ambGlow(alpha: 0.0)] as CFArray
        let locs: [CGFloat] = [0.00, 0.55, 1.00]

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors,
                                        locations: locs) else { return }

        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: cx-radius, y: cy-radius,
                                   width: radius*2, height: radius*2))
        ctx.clip()
        let c = CGPoint(x: cx, y: cy)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: radius,
                               options: .drawsAfterEndLocation)
        ctx.restoreGState()
    }

    // MARK: - drawArcs

    private func drawArcs(_ ctx: CGContext, t: Double, cx: Double, cy: Double, R: Double,
                          numArcs: Int, arcAlpha: Double) {
        let radii:      [Double] = [0.45, 0.65, 0.85, 0.95]
        let periods:    [Double] = [12.0, 18.0, 25.0, -20.0]
        let arcLengths: [Double] = [1.047, 1.047, 2.094, 2.967]
        let isAwakening = (phase == .digitalAwakening)

        for i in 0 ..< min(numArcs, 4) {
            let arcR      = radii[i] * R
            let tilt      = Self.arcTilts[i]
            let rotAngle  = (t / periods[i]) * .pi * 2.0
            let arcLength = arcLengths[min(i, arcLengths.count-1)]

            var eff = arcAlpha
            if isAwakening {
                let noise = 0.5 + 0.5*sin(t*3.7 + Double(i)*2.3)
                          + 0.3*sin(t*7.1 + Double(i)*1.1)
                eff *= max(0.0, min(1.0, noise*0.6))
            }
            guard eff > 0.01 else { continue }

            let rx = arcR
            let ry = arcR * cos(tilt)
            let steps = max(24, Int(arcLength / (.pi*2) * 96))
            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for s in 0...steps {
                let ang = rotAngle + arcLength * Double(s) / Double(steps)
                pts.append(CGPoint(x: cx + rx*cos(ang), y: cy + ry*sin(ang)))
            }
            guard pts.count >= 2 else { continue }

            let path = CGMutablePath()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }

            for (color, width) in [
                (Self.ambGlow(alpha: eff*0.25), CGFloat(4.0)),
                (Self.ambCore(alpha: eff*0.75), CGFloat(1.5)),
                (Self.ambHot(alpha:  eff*0.40), CGFloat(0.4))
            ] {
                ctx.saveGState()
                ctx.setStrokeColor(color)
                ctx.setLineWidth(width)
                ctx.setLineCap(.round)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    // MARK: - drawFlares

    private func drawFlares(_ ctx: CGContext, t: Double, phaseT: Double,
                             cx: Double, cy: Double, R: Double, params: OrbParams) {
        let period    = 1.0 / max(0.001, params.flareRate)
        let dutyCycle = 0.35
        let maxFlares = (phase == .voiceReceived) ? 6 : 3

        for i in 0..<maxFlares {
            let progress = (t/period + Double(i)/Double(maxFlares))
                           .truncatingRemainder(dividingBy: 1.0)
            guard progress < dutyCycle else { continue }
            drawFlare(ctx, cx: cx, cy: cy,
                      angle:    Self.flareAngles[i % Self.flareAngles.count],
                      curve:    Self.flareCurves[i % Self.flareCurves.count],
                      progress: progress / dutyCycle,
                      maxLen:   params.flareMaxLen * R,
                      alpha:    params.flareAlpha)
        }

        if phase == .voiceReceived && phaseT < 1.5 {
            for i in 0..<3 {
                let eT = phaseT - Double(i)*0.1
                guard eT >= 0 else { continue }
                drawFlare(ctx, cx: cx, cy: cy,
                          angle:    Self.flareAngles[i] + 0.52,
                          curve:    Self.flareCurves[(i+3) % Self.flareCurves.count],
                          progress: min(1.0, eT/1.2),
                          maxLen:   params.flareMaxLen * R * 1.35,
                          alpha:    params.flareAlpha * 1.15)
            }
        }
    }

    private func drawFlare(_ ctx: CGContext, cx: Double, cy: Double,
                            angle: Double, curve: Double,
                            progress: Double, maxLen: Double, alpha: Double) {
        let extFrac  = progress < 0.4 ? progress/0.4 : 1.0
        let fadeFrac = progress < 0.4 ? 1.0 : pow(1.0-(progress-0.4)/0.6, 0.6)
        let ea       = alpha * extFrac * fadeFrac
        guard ea > 0.01 else { return }

        let coreEdge = 0.06*(extFrac*0.3+0.7)
        let startX = cx + cos(angle)*coreEdge*maxLen/0.55
        let startY = cy + sin(angle)*coreEdge*maxLen/0.55
        let tipX   = cx + cos(angle)*maxLen*extFrac
        let tipY   = cy + sin(angle)*maxLen*extFrac
        let perp   = angle + .pi/2.0
        let cpX    = cx + cos(angle)*maxLen*extFrac*0.5 + cos(perp)*curve*maxLen
        let cpY    = cy + sin(angle)*maxLen*extFrac*0.5 + sin(perp)*curve*maxLen

        let path = CGMutablePath()
        path.move(to: CGPoint(x: startX, y: startY))
        path.addQuadCurve(to:    CGPoint(x: tipX, y: tipY),
                          control: CGPoint(x: cpX,   y: cpY))

        for (color, width) in [
            (Self.ambGlow(alpha: ea*0.55), CGFloat(8.0)),
            (Self.ambCore(alpha: ea*0.85), CGFloat(2.5)),
            (Self.ambHot(alpha:  ea*0.60), CGFloat(0.6))
        ] {
            ctx.saveGState()
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - drawSparks

    private func drawSparks(_ ctx: CGContext, t: Double, cx: Double, cy: Double, R: Double,
                            numSparks: Int, sparkSpeed: Double, sparkMaxR: Double) {
        for i in 0..<min(numSparks, Self.sparkAngles.count) {
            let angle    = Self.sparkAngles[i]
            let progress = ((t/sparkSpeed) + Double(i)/Double(numSparks))
                           .truncatingRemainder(dividingBy: 1.0)
            let sa = sin(progress * .pi)
            guard sa > 0.01 else { continue }

            let dist  = 0.06*R + progress*(sparkMaxR*R - 0.06*R)
            let wobble = sin(progress * .pi * 2.0) * 8.0
            let perp   = angle + .pi/2.0
            let px = cx + cos(angle)*dist + cos(perp)*wobble
            let py = cy + sin(angle)*dist + sin(perp)*wobble

            drawSpark(ctx, px: px, py: py, alpha: sa)
        }
    }

    private func drawSpark(_ ctx: CGContext, px: Double, py: Double, alpha: Double) {
        let outerR = 8.0
        let innerR = 3.0

        let colors: CFArray = [
            Self.white(alpha:  alpha),
            Self.ambHot(alpha:  alpha*0.75),
            Self.ambCore(alpha: alpha*0.30),
            Self.ambGlow(alpha: 0.0)
        ] as CFArray
        let locs: [CGFloat] = [0.00, 0.35, 0.70, 1.00]

        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors, locations: locs) {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: px-outerR, y: py-outerR,
                                      width: outerR*2, height: outerR*2))
            ctx.clip()
            let c = CGPoint(x: px, y: py)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                   endCenter: c, endRadius: outerR,
                                   options: .drawsAfterEndLocation)
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.setFillColor(Self.white(alpha: alpha*0.90))
        ctx.addEllipse(in: CGRect(x: px-innerR, y: py-innerR,
                                   width: innerR*2, height: innerR*2))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - Utilities

    private func easeOut(_ t: Double) -> Double {
        1.0 - pow(1.0 - t, 3.0)
    }
}

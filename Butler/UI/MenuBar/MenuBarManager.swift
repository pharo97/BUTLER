import AppKit

// MARK: - MenuBarManager

/// Owns the persistent NSStatusItem that lives in the system menu bar.
///
/// BUTLER presents itself as a menu bar app (LSUIElement = true, no Dock icon).
/// The status item is always visible — permanently anchored next to WiFi / Bluetooth.
///
/// ## Click behaviour
///
///   Left-click   → activate Glass Chamber + start listening (same as ⌥Space)
///   Right-click  → contextual menu  (Talk, Show/Hide, Settings, Quit)
///
/// ## Icon states
///
///   Idle         →  `waveform`          (quiet branded mark)
///   Listening    →  mic pulse animation  (mic → mic.fill → waveform cycling)
///   Thinking     →  `ellipsis.bubble`
///   Deep Think   →  `cpu`
///   Speaking     →  **live 8-bar waveform** redrawn at 30 fps, height-driven by
///                   the actual TTS amplitude piped in from VoiceSystem
///   Learning     →  `sparkles`
///
/// The waveform icon is drawn with Core Graphics (NSBezierPath) rather than
/// SF Symbols so every frame is unique. It uses `isTemplate = true` so macOS
/// automatically inverts it for dark / light menu bars.
@MainActor
final class MenuBarManager {

    // MARK: - Private state

    private let statusItem: NSStatusItem
    private weak var panel: NSPanel?
    private weak var voiceSystem: VoiceSystem?

    private var currentState: VisualizationEngine.PulseState = .idle

    // MARK: - Animation

    /// Shared timer for all animated states.
    private var animationTimer: Timer?
    /// Monotonic phase counter for waveform sine sweep (radians).
    private var wavePhase: Double = 0
    /// Frame index for the listening mic-cycle animation.
    private var listenFrame: Int = 0

    /// SF Symbol names cycled during the listening state.
    private static let listenFrames: [String] = [
        "mic",
        "mic.fill",
        "waveform",
        "mic.fill"
    ]

    // MARK: - Init

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configure()
    }

    // MARK: - Wiring (called by AppDelegate after dependencies exist)

    func setPanel(_ panel: NSPanel) {
        self.panel = panel
    }

    /// Connect VoiceSystem so the waveform animation can read live amplitude.
    func setVoiceSystem(_ vs: VoiceSystem) {
        self.voiceSystem = vs
    }

    // MARK: - State updates

    /// Called by `VisualizationEngine.onStateChange`.
    func updateIcon(for state: VisualizationEngine.PulseState) {
        guard state != currentState else { return }
        currentState = state

        stopAnimation()

        switch state {
        case .idle:
            setSymbol("waveform")
        case .listening:
            startListenAnimation()
        case .thinking:
            setSymbol("ellipsis.bubble")
        case .deepThinking:
            setSymbol("cpu")
        case .speaking:
            startWaveformAnimation()
        case .learning:
            setSymbol("sparkles")
        }
    }

    // MARK: - Setup

    private func configure() {
        guard let button = statusItem.button else { return }
        setSymbol("waveform")
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick(_:))
        button.target = self
        button.toolTip = "BUTLER — click to speak"
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            activateListening()
        }
    }

    // MARK: - Left-click: activate listening

    private func activateListening() {
        // Show panel if hidden
        if let panel, !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        // Trigger voice activation — same path as ⌥Space
        voiceSystem?.activationRequested = true
    }

    // MARK: - Right-click: context menu

    private func showContextMenu() {
        let menu = NSMenu()

        // Primary action — "Talk to BUTLER"
        let talkItem = menu.addItem(
            withTitle: "Talk to BUTLER",
            action:    #selector(talkAction),
            keyEquivalent: ""
        )
        talkItem.target = self
        talkItem.image  = NSImage(systemSymbolName: "mic.fill",
                                   accessibilityDescription: nil)

        menu.addItem(.separator())

        // Panel visibility toggle
        let panelVisible = panel?.isVisible ?? false
        let toggleTitle  = panelVisible ? "Hide Glass Chamber" : "Show Glass Chamber"
        let toggleItem   = menu.addItem(
            withTitle: toggleTitle,
            action:    #selector(togglePanel),
            keyEquivalent: ""
        )
        toggleItem.target = self

        menu.addItem(.separator())

        let settingsItem = menu.addItem(
            withTitle: "Settings…",
            action:    #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self

        menu.addItem(.separator())

        let quitItem = menu.addItem(
            withTitle: "Quit BUTLER",
            action:    #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp

        // Show menu attached to the status item
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // clear so the next left-click activates listening, not menu
    }

    // MARK: - Menu actions

    @objc private func talkAction() {
        activateListening()
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openSettings() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .butlerShowSettings, object: nil)
    }

    // MARK: - Animation helpers

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        wavePhase  = 0
        listenFrame = 0
    }

    // ── Listening: cycling mic symbols at ~350 ms ──────────────────────────

    private func startListenAnimation() {
        listenFrame = 0
        setSymbol(Self.listenFrames[0])

        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 0.35,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.listenFrame = (self.listenFrame + 1) % Self.listenFrames.count
                self.setSymbol(Self.listenFrames[self.listenFrame])
            }
        }
    }

    // ── Speaking: live 8-bar waveform at 30 fps ────────────────────────────

    private func startWaveformAnimation() {
        // Kick off with an immediate frame so there's no blank flash
        renderWaveframe()

        // .common mode keeps the timer firing during window drag / menu tracking
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.renderWaveframe() }
        }
        RunLoop.main.add(t, forMode: .common)
        animationTimer = t
    }

    private func renderWaveframe() {
        // Advance phase ~2.4 radians/sec  (0.08 rad × 30 fps)
        wavePhase += 0.08
        let amp = voiceSystem?.amplitude ?? 0
        guard let button = statusItem.button else { return }
        button.image = waveformImage(amplitude: amp, phase: wavePhase)
    }

    // MARK: - Waveform drawing

    /// Renders an 8-bar equaliser icon into a 22 × 18-pt template NSImage.
    ///
    /// - `amplitude` drives bar height [0, 1] from actual TTS audio energy.
    /// - `phase` is a monotonic angle (radians) that sweeps a sine wave across
    ///    the bars to produce the ripple effect even when amplitude is low.
    private func waveformImage(amplitude amp: Double, phase: Double) -> NSImage {
        let ptSize = NSSize(width: 22, height: 18)

        // Render at 2× for Retina sharpness
        let scale: CGFloat = 2
        let pxSize = NSSize(width: ptSize.width * scale, height: ptSize.height * scale)

        let image = NSImage(size: ptSize)
        image.lockFocusFlipped(false)

        // ── Bar geometry ───────────────────────────────────────────────────
        let n         = 8                         // bar count
        let barW: CGFloat = 2.0                   // pt
        let gapW: CGFloat = 1.0                   // pt between bars
        let totalW    = CGFloat(n) * barW + CGFloat(n - 1) * gapW
        let originX   = (ptSize.width  - totalW) / 2
        let midY      = ptSize.height / 2
        let maxH: CGFloat = 14.0
        let minH: CGFloat = 1.5

        // Centre-weighted envelope: outer bars shorter = natural waveform silhouette
        let envelope: [Double] = [0.38, 0.58, 0.80, 1.00, 1.00, 0.80, 0.58, 0.38]
        // Per-bar phase offset creates the rolling wave ripple
        let offsets:  [Double] = [0.00, 0.55, 1.10, 1.65, 2.20, 1.10, 0.55, 0.00]

        NSColor.white.setFill()

        for i in 0 ..< n {
            let x = originX + CGFloat(i) * (barW + gapW)

            // 0.65 of height comes from amplitude × envelope weight.
            // 0.35 comes from a sine sweep so bars stay alive even at amp ≈ 0.
            let sinVal  = (sin(phase + offsets[i]) * 0.5 + 0.5)    // [0, 1]
            let driven  = max(0, min(1, amp)) * envelope[i]
            let height  = max(minH, CGFloat(driven * 0.65 + sinVal * 0.35 * 0.45 + 0.04) * maxH)

            let bar = NSRect(
                x:      x,
                y:      midY - height / 2,
                width:  barW,
                height: height
            )
            NSBezierPath(roundedRect: bar, xRadius: 1.0, yRadius: 1.0).fill()
        }

        image.unlockFocus()
        image.isTemplate = true     // auto-inverts for dark/light menu bar
        _ = pxSize                  // silence unused-variable warning
        return image
    }

    // MARK: - Icon helper

    private func setSymbol(_ name: String) {
        guard let button = statusItem.button else { return }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: name)
        img?.isTemplate = true
        button.image = img
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let butlerShowSettings      = Notification.Name("butlerShowSettings")
    static let butlerConversationError = Notification.Name("butlerConversationError")
}

import AppKit
import AVFoundation
import WebKit

// MARK: - BirthPhaseViewController

/// Pure AppKit view controller for the BUTLER birth sequence (onboarding).
///
/// ## Why pure AppKit?
///
/// macOS 26 beta (25C56) has a bug: `swift_task_isCurrentExecutorWithFlagsImpl`
/// dereferences an invalid MainActor isa pointer. SwiftUI's private
/// `AppKitEventBindingBridge` attaches itself to every NSView inside an
/// NSHostingView and intercepts ALL NSGestureRecognizer actions, re-routing them
/// through this broken executor check. No workaround exists inside SwiftUI.
///
/// This controller uses:
/// - NSVisualEffectView for glass background
/// - BirthOrbNSView (CALayerDelegate / CVDisplayLink) for phases dormant–voiceReceived
/// - WKWebView for the WebGL pulse orb in phases discovery–complete
/// - NSTableView with pure ObjC target/action for voice selection
/// - NSTextField for all text display
/// - An 80 ms NSTimer to poll coordinator state (no @Observable, no withObservationTracking)
///
/// Result: zero AppKitEventBindingBridge involvement, zero SwiftUI AttributeGraph
/// executor checks, deterministic crash eliminated.
@MainActor
final class BirthPhaseViewController: NSViewController {

    // MARK: - Dependencies

    private let coordinator: BirthPhaseCoordinator
    private let engine: VisualizationEngine

    // MARK: - UI Components

    private var orbContainerView: NSView!
    private var birthOrbView: BirthOrbNSView!
    private var pulseWebView: WKWebView!
    private var textLabel: NSTextField!
    private var voiceTableScrollView: NSScrollView!
    private var voiceTableView: NSTableView!
    private var micIndicatorView: NSView!
    private var skipButton: NSButton!

    // MARK: - State

    private var updateTimer: Timer?
    private var availableVoices: [AVSpeechSynthesisVoice] = []
    private var previewSynth = AVSpeechSynthesizer()
    private var previewingID: String? = nil
    private var lastPhase: BirthPhase? = nil
    private var lastBootText: String = ""
    private var lastDisplayText: String = ""
    private var micPulseTimer: Timer?
    private var lastSpeakingState: Bool? = nil

    // MARK: - Init

    init(coordinator: BirthPhaseCoordinator, engine: VisualizationEngine) {
        self.coordinator = coordinator
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - View Lifecycle

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 700))
        root.wantsLayer = true
        root.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.view = root
        buildUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startUpdateTimer()
        // Kick off the coordinator's async sequence now that the view is on screen.
        coordinator.begin()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopUpdateTimer()
        stopMicPulse()
        previewSynth.stopSpeaking(at: .immediate)
    }

    // MARK: - Build UI

    private func buildUI() {
        // ── Glass background ────────────────────────────────────────────────────
        let blur = NSVisualEffectView(frame: view.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .sidebar
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 24
        blur.layer?.masksToBounds = true
        view.addSubview(blur)

        // Border ring on top of the blur layer
        let borderLayer = CAShapeLayer()
        borderLayer.frame = view.bounds
        let borderPath = CGPath(
            roundedRect: view.bounds.insetBy(dx: 0.25, dy: 0.25),
            cornerWidth: 24, cornerHeight: 24,
            transform: nil
        )
        borderLayer.path = borderPath
        borderLayer.fillColor = .none
        borderLayer.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)
        borderLayer.lineWidth = 0.5
        view.wantsLayer = true
        view.layer?.addSublayer(borderLayer)

        // ── Skip button (top-right) ─────────────────────────────────────────────
        skipButton = NSButton(title: "Skip", target: self, action: #selector(skipTapped))
        skipButton.isBordered = false
        skipButton.frame = NSRect(x: 555, y: 655, width: 50, height: 25)
        var skipAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            .font: NSFont.systemFont(ofSize: 12, weight: .regular)
        ]
        skipButton.attributedTitle = NSAttributedString(string: "Skip", attributes: skipAttrs)
        view.addSubview(skipButton)

        // ── Orb container (centered horizontally: (620-280)/2 = 170) ───────────
        orbContainerView = NSView(frame: NSRect(x: 170, y: 340, width: 280, height: 280))
        orbContainerView.wantsLayer = true
        view.addSubview(orbContainerView)

        // BirthOrbNSView — phases dormant through voiceReceived
        birthOrbView = BirthOrbNSView(frame: orbContainerView.bounds)
        birthOrbView.autoresizingMask = [.width, .height]
        orbContainerView.addSubview(birthOrbView)

        // WKWebView — phases discovery through complete
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        pulseWebView = WKWebView(frame: orbContainerView.bounds, configuration: config)
        pulseWebView.autoresizingMask = [.width, .height]
        pulseWebView.setValue(false, forKey: "drawsBackground")
        if let url = Bundle.main.url(forResource: "pulse", withExtension: "html") {
            let dir = url.deletingLastPathComponent()
            pulseWebView.loadFileURL(url, allowingReadAccessTo: dir)
        }
        pulseWebView.isHidden = true
        orbContainerView.addSubview(pulseWebView)

        // ── Text label ──────────────────────────────────────────────────────────
        textLabel = NSTextField(wrappingLabelWithString: "")
        textLabel.frame = NSRect(x: 60, y: 270, width: 500, height: 60)
        textLabel.textColor = .white
        textLabel.backgroundColor = .clear
        textLabel.drawsBackground = false
        textLabel.isBezeled = false
        textLabel.isEditable = false
        textLabel.alignment = .center
        textLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textLabel.isHidden = true
        view.addSubview(textLabel)

        // ── Voice selection table ───────────────────────────────────────────────
        voiceTableView = NSTableView()
        voiceTableView.backgroundColor = .clear
        voiceTableView.headerView = nil
        voiceTableView.rowHeight = 52
        voiceTableView.selectionHighlightStyle = .none
        voiceTableView.intercellSpacing = NSSize(width: 0, height: 4)
        voiceTableView.dataSource = self
        voiceTableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("voice"))
        column.width = 500
        voiceTableView.addTableColumn(column)

        voiceTableScrollView = NSScrollView(frame: NSRect(x: 60, y: 50, width: 500, height: 210))
        voiceTableScrollView.documentView = voiceTableView
        voiceTableScrollView.drawsBackground = false
        voiceTableScrollView.hasVerticalScroller = true
        voiceTableScrollView.autohidesScrollers = true
        voiceTableScrollView.backgroundColor = .clear
        voiceTableScrollView.enclosingScrollView?.backgroundColor = .clear
        voiceTableScrollView.isHidden = true
        view.addSubview(voiceTableScrollView)

        // ── Mic indicator (pulsing red dot during questioning) ──────────────────
        micIndicatorView = NSView(frame: NSRect(x: 290, y: 140, width: 40, height: 40))
        micIndicatorView.wantsLayer = true
        micIndicatorView.layer?.cornerRadius = 20
        micIndicatorView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
        micIndicatorView.isHidden = true
        view.addSubview(micIndicatorView)
    }

    // MARK: - Update Timer

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.syncUI()
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - syncUI

    /// Polls coordinator state every 80 ms and updates views directly.
    /// No @Observable, no withObservationTracking, no SwiftUI.
    @objc private func syncUI() {
        let phase       = coordinator.phase
        let bootText    = coordinator.bootText
        let displayText = coordinator.displayText
        let isSpeaking  = coordinator.isSpeakingNow
        let isListening = coordinator.isListeningForAnswer

        // Phase transition
        if phase != lastPhase {
            handlePhaseTransition(to: phase, from: lastPhase)
            lastPhase = phase
        }

        // Text updates — boot text takes priority while in booting phase
        if phase == .booting {
            if bootText != lastBootText && !bootText.isEmpty {
                textLabel.stringValue = bootText
                lastBootText = bootText
            }
        } else if displayText != lastDisplayText && !displayText.isEmpty {
            textLabel.stringValue = displayText
            lastDisplayText = displayText
        }

        // Mic indicator visibility is driven by isListening flag
        if phase == .questioning {
            micIndicatorView.isHidden = !isListening
        }

        // Orb state for WebGL phases (discovery onward)
        if phaseRank(phase) >= phaseRank(.discovery) {
            updatePulseWebView(isSpeaking: isSpeaking)
        }

        // Keep BirthOrbNSView in sync for pre-discovery phases
        if phaseRank(phase) < phaseRank(.discovery) {
            birthOrbView.orbPhase = phase
            birthOrbView.orbIsSpeaking = isSpeaking
        }
    }

    // MARK: - Phase Transition

    private func handlePhaseTransition(
        to phase: BirthPhase,
        from prev: BirthPhase?
    ) {
        switch phase {
        case .dormant:
            birthOrbView.isHidden = false
            pulseWebView.isHidden = true
            voiceTableScrollView.isHidden = true
            micIndicatorView.isHidden = true
            textLabel.isHidden = true
            birthOrbView.orbPhase = .dormant
            birthOrbView.orbIsSpeaking = false

        case .booting:
            textLabel.isHidden = false
            textLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            birthOrbView.orbPhase = .booting

        case .digitalAwakening:
            textLabel.isHidden = false
            textLabel.font = NSFont.systemFont(ofSize: 15, weight: .light)
            birthOrbView.orbPhase = .digitalAwakening
            loadVoices()
            voiceTableScrollView.isHidden = false
            voiceTableView.reloadData()

        case .voiceReceived:
            voiceTableScrollView.isHidden = true
            previewSynth.stopSpeaking(at: .immediate)
            previewingID = nil
            birthOrbView.orbPhase = .voiceReceived

        case .discovery:
            birthOrbView.isHidden = true
            pulseWebView.isHidden = false
            micIndicatorView.isHidden = true
            lastSpeakingState = nil   // force a JS call on next sync

        case .questioning:
            birthOrbView.isHidden = true
            pulseWebView.isHidden = false
            startMicPulse()

        case .declaring:
            birthOrbView.isHidden = true
            pulseWebView.isHidden = false
            stopMicPulse()
            micIndicatorView.isHidden = true

        case .complete:
            stopMicPulse()
        }
    }

    // MARK: - Phase rank helper (BirthPhase has no rawValue)

    private func phaseRank(_ phase: BirthPhase) -> Int {
        switch phase {
        case .dormant:          return 0
        case .booting:          return 1
        case .digitalAwakening: return 2
        case .voiceReceived:    return 3
        case .discovery:        return 4
        case .questioning:      return 5
        case .declaring:        return 6
        case .complete:         return 7
        }
    }

    // MARK: - PulseWebView update

    private func updatePulseWebView(isSpeaking: Bool) {
        guard lastSpeakingState != isSpeaking else { return }
        lastSpeakingState = isSpeaking
        let amplitude = isSpeaking ? 0.8 : 0.2
        let state = isSpeaking ? "speaking" : "idle"
        pulseWebView.evaluateJavaScript(
            "window.butler?.setState('\(state)', \(amplitude));",
            completionHandler: nil
        )
    }

    // MARK: - Mic pulse animation

    private func startMicPulse() {
        guard micPulseTimer == nil else { return }
        micIndicatorView.isHidden = false
        micIndicatorView.alphaValue = 1.0
        micPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.micIndicatorView.animator().alphaValue =
                    self.micIndicatorView.alphaValue < 0.5 ? 1.0 : 0.3
            }
        }
    }

    private func stopMicPulse() {
        micPulseTimer?.invalidate()
        micPulseTimer = nil
        micIndicatorView.isHidden = true
        micIndicatorView.alphaValue = 1.0
    }

    // MARK: - Voice loading

    private func loadVoices() {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        availableVoices = all
            .filter { $0.language.hasPrefix(locale) }
            .sorted { a, b in
                let ra = qualityRank(a.quality)
                let rb = qualityRank(b.quality)
                if ra != rb { return ra > rb }
                return a.name < b.name
            }
        if availableVoices.isEmpty {
            availableVoices = all.sorted { $0.name < $1.name }
        }
    }

    private func qualityRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium:  return 3
        case .enhanced: return 2
        default:        return 1
        }
    }

    private func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> NSTextField {
        let label: NSTextField
        switch q {
        case .premium:
            label = NSTextField(labelWithString: "PREMIUM")
            label.textColor = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        case .enhanced:
            label = NSTextField(labelWithString: "ENHANCED")
            label.textColor = NSColor(calibratedRed: 0.55, green: 0.72, blue: 1.0, alpha: 1.0)
        default:
            label = NSTextField(labelWithString: "STANDARD")
            label.textColor = NSColor.white.withAlphaComponent(0.5)
        }
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        label.drawsBackground = false
        label.isBezeled = false
        return label
    }

    // MARK: - Button actions (pure ObjC target/action — no Swift concurrency)

    @objc private func skipTapped() {
        coordinator.skip()
    }

    @objc private func previewVoiceTapped(_ sender: NSButton) {
        guard sender.tag < availableVoices.count else { return }
        let voice = availableVoices[sender.tag]
        if previewingID == voice.identifier {
            previewSynth.stopSpeaking(at: .immediate)
            previewingID = nil
            return
        }
        previewSynth.stopSpeaking(at: .immediate)
        previewingID = voice.identifier
        let utt = AVSpeechUtterance(string: "Hello, I am \(voice.name). I will be your voice.")
        utt.voice = voice
        previewSynth.speak(utt)
    }

    @objc private func selectVoiceTapped(_ sender: NSButton) {
        guard sender.tag < availableVoices.count else { return }
        let voice = availableVoices[sender.tag]
        previewSynth.stopSpeaking(at: .immediate)
        previewingID = nil
        UserDefaults.standard.set(voice.identifier, forKey: "butler.tts.voiceIdentifier")
        UserDefaults.standard.set(voice.identifier, forKey: "butler.selectedVoiceIdentifier.v1")
        // voiceWasSelected() takes no arguments — voice ID already persisted above
        coordinator.voiceWasSelected()
    }
}

// MARK: - NSTableViewDataSource

extension BirthPhaseViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        availableVoices.count
    }
}

// MARK: - NSTableViewDelegate

extension BirthPhaseViewController: NSTableViewDelegate {

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard row < availableVoices.count else { return nil }
        let voice = availableVoices[row]

        let cell = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 52))
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        cell.layer?.cornerRadius = 8

        // Voice name label
        let nameLabel = NSTextField(labelWithString: voice.name)
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.drawsBackground = false
        nameLabel.isBezeled = false
        nameLabel.frame = NSRect(x: 12, y: 26, width: 280, height: 18)
        cell.addSubview(nameLabel)

        // Language label
        let langLabel = NSTextField(labelWithString: voice.language)
        langLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        langLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        langLabel.drawsBackground = false
        langLabel.isBezeled = false
        langLabel.frame = NSRect(x: 12, y: 10, width: 120, height: 14)
        cell.addSubview(langLabel)

        // Quality badge
        let badge = qualityLabel(voice.quality)
        badge.frame = NSRect(x: 140, y: 10, width: 90, height: 14)
        cell.addSubview(badge)

        // Preview button (speaker icon)
        let previewBtn = NSButton(frame: NSRect(x: 370, y: 12, width: 28, height: 28))
        previewBtn.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Preview")
        previewBtn.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        previewBtn.isBordered = false
        previewBtn.tag = row
        previewBtn.target = self
        previewBtn.action = #selector(previewVoiceTapped(_:))
        cell.addSubview(previewBtn)

        // Select button
        let selectBtn = NSButton(frame: NSRect(x: 406, y: 12, width: 80, height: 28))
        selectBtn.title = "Select"
        selectBtn.bezelStyle = .rounded
        selectBtn.tag = row
        selectBtn.target = self
        selectBtn.action = #selector(selectVoiceTapped(_:))
        cell.addSubview(selectBtn)

        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        52
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = NSTableRowView()
        rv.isEmphasized = false
        return rv
    }
}

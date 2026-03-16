import SwiftUI
import AppKit

/// Root SwiftUI view hosted inside GlassChamberPanel.
///
/// Phase 2 layout (top → bottom, 280 × 460):
///   ┌─────────────────────────┐
///   │   Holographic orb (220pt)│  ← WebGL gyroscopic orb (PulseWebView)
///   │   BUTLER wordmark       │
///   │   Status + context badge│  ← new: shows detected app context
///   │   Conversation panel    │  ← streaming text + last exchange
///   │   Mic button            │  ← push-to-talk
///   └─────────────────────────┘
struct GlassChamberView: View {

    // @Observable — SwiftUI auto-tracks any property accessed in body.
    var engine:             VisualizationEngine
    var voiceSystem:        VoiceSystem
    var aiLayer:            AIIntegrationLayer
    var activityMonitor:    ActivityMonitor
    var hotkeyManager:      HotkeyManager
    var perception:         PerceptionLayer
    var automationEngine:   AutomationEngine
    var companionEngine:    CompanionEngine
    // Phase 2 additions
    var tierManager:         PermissionTierManager
    var learningSystem:      LearningSystem
    var interventionEngine:  InterventionEngine
    var rhythmTracker:       DailyRhythmTracker
    var permissionSecurity:  PermissionSecurityManager
    var audioDeviceManager:  AudioDeviceManager
    var idleProcessor:       IdleBackgroundProcessor

    // MARK: - Local state
    @State private var conversationTask:    Task<Void, Never>?
    @State private var apiKeyDraft:         String = ""
    @State private var errorMessage:        String? = nil
    @State private var showSettings:        Bool   = false
    @State private var showDebug:           Bool   = false
    /// Toggle from the right-click context menu — shows state buttons for dev testing.
    @State private var showDebugControls:   Bool   = false

    // MARK: - Personality / name (live-updating from UserDefaults)
    /// Reflects the user-configured AI display name. Falls back to "BUTLER".
    @AppStorage("butler.ai.customName") private var aiCustomName: String = "BUTLER"

    // MARK: - Body

    var body: some View {
        ZStack {
            glassBackground

            VStack(spacing: 0) {
                // Holographic pulse visualization (WebGL orb)
                PulseWebView(
                    state:     engine.pulseState.rawValue,
                    amplitude: engine.amplitude
                )
                .frame(height: 220)

                // BUTLER wordmark + status + context badge
                identity
                    .padding(.top, 4)

                // Streaming / last conversation exchange
                conversationPanel
                    .frame(height: 100)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Push-to-talk mic button
                micButton
                    .padding(.top, 10)

                // ── Dev state controls ─────────────────────────────────────────
                // Right-click → "Show State Controls" to toggle during development.
                if showDebugControls {
                    testControls
                        .padding(.bottom, 8)
                } else {
                    Spacer().frame(height: 18)
                }
            }
        }
        .frame(width: 280, height: 460)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        // Gear icon — top-right, always accessible
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(14)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        // Dismiss button — slides in from top during proactive speech only.
        // Tapping it stops speech immediately and records a dismissal signal
        // so BUTLER learns to back off in this context.
        .overlay(alignment: .top) {
            if companionEngine.isProactiveSpeaking {
                Button {
                    voiceSystem.stopSpeaking()
                    companionEngine.recordDismissed()
                    haptic()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Dismiss")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(0.4)
                    }
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.10))
                            .overlay(
                                Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.75), value: companionEngine.isProactiveSpeaking)
        // Right-click context menu
        .contextMenu {
            Button { showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button { showDebug = true } label: {
                Label("Debug Panel", systemImage: "cpu")
            }
            Button { showDebugControls.toggle() } label: {
                Label(
                    showDebugControls ? "Hide State Controls" : "Show State Controls",
                    systemImage: showDebugControls ? "slider.horizontal.3" : "slider.horizontal.3"
                )
            }
            Button { aiLayer.clearApiKey() } label: {
                Label("Reset API Key", systemImage: "key.slash")
            }
            Divider()
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label("Quit BUTLER", systemImage: "power")
            }
        }
        // Bridge voice amplitude → visualization engine at ~30 fps
        .task {
            while !Task.isCancelled {
                engine.setAmplitude(voiceSystem.amplitude)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        // Hotkey bridge — ⌥Space fires from HotkeyManager → activationRequested → here
        .onChange(of: voiceSystem.activationRequested) { _, requested in
            if requested {
                voiceSystem.activationRequested = false
                handleMicTapped()
            }
        }
        // MenuBar "Settings…" menu item → open settings sheet
        .onReceive(NotificationCenter.default.publisher(for: .butlerShowSettings)) { _ in
            showSettings = true
        }
        // Continuous conversation error → transient red banner
        .onReceive(NotificationCenter.default.publisher(for: .butlerConversationError)) { note in
            let msg = note.object as? String ?? "Something went wrong."
            withAnimation { errorMessage = msg }
        }
        // API key setup — shown on first launch when no key is in Keychain
        .sheet(isPresented: Binding(
            get: { aiLayer.showApiKeySetup },
            set: { _ in }
        )) {
            apiKeySetupSheet
        }
        // Settings sheet — voice, hotkey, provider, permission tiers, audio devices
        .sheet(isPresented: $showSettings) {
            SettingsView(
                voiceProfile:       voiceSystem.voiceProfile,
                aiLayer:            aiLayer,
                hotkeyManager:      hotkeyManager,
                tierManager:        tierManager,
                audioDeviceManager: audioDeviceManager,
                idleProcessor:      idleProcessor
            )
            .onAppear { audioDeviceManager.refresh() }
        }
        // Debug panel — long-press the BUTLER wordmark
        .sheet(isPresented: $showDebug) {
            DebugPanelView(
                learningSystem:     learningSystem,
                interventionEngine: interventionEngine,
                activityMonitor:    activityMonitor,
                rhythmTracker:      rhythmTracker,
                permissionSecurity: permissionSecurity
            )
        }
        // Transient error banner
        .overlay(alignment: .bottom) {
            if let msg = errorMessage {
                Text(msg)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.red.opacity(0.40)))
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { errorMessage = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: errorMessage)
    }

    // MARK: - Glass background

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors:     [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint:   .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(spacing: 4) {
            // Long-press AI name wordmark to open debug panel.
            // The name is read live from UserDefaults via @AppStorage("butler.ai.customName").
            Text(aiCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "BUTLER"
                 : aiCustomName.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.50))
                .tracking(5)
                .onLongPressGesture(minimumDuration: 1.5) { showDebug = true }

            // Status text (Listening… / Thinking… / Ready)
            Text(engine.statusText)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.white.opacity(0.28))
                .animation(.easeInOut(duration: 0.25), value: engine.statusText)

            // Context badge — shows detected app context when BUTLER is idle
            contextBadge
        }
    }

    /// Subtle one-liner showing what BUTLER thinks the user is doing.
    /// Only visible when idle so it doesn't compete with status messages.
    @ViewBuilder
    private var contextBadge: some View {
        let ctx = activityMonitor.context
        let suppressed = activityMonitor.isVideoCall ||
                         activityMonitor.isScreenSharing

        if engine.pulseState == .idle && ctx != .unknown {
            HStack(spacing: 4) {
                // Suppressed = red dot (BUTLER is silent), active = context color dot
                Circle()
                    .fill(suppressed ? Color.red.opacity(0.70) : contextColor(ctx).opacity(0.70))
                    .frame(width: 4, height: 4)

                Text(suppressed ? "Silent" : ctx.displayName)
                    .font(.system(size: 7.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.22))
                    .tracking(0.5)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            .animation(.easeInOut(duration: 0.35), value: ctx)
            .animation(.easeInOut(duration: 0.35), value: suppressed)
        }
    }

    /// Accent color per context — used for the tiny status dot.
    private func contextColor(_ ctx: ButlerContext) -> Color {
        switch ctx {
        case .coding:       Color(red: 0.35, green: 1.00, blue: 0.72)  // aqua
        case .writing:      Color(red: 0.80, green: 0.90, blue: 1.00)  // pale blue
        case .browsing:     Color(red: 1.00, green: 0.92, blue: 0.60)  // gold
        case .comms:        Color(red: 0.75, green: 0.45, blue: 1.00)  // purple
        case .videoCall:    Color.red
        case .creative:     Color(red: 1.00, green: 0.55, blue: 0.35)  // coral
        case .productivity: Color(red: 0.55, green: 0.85, blue: 0.55)  // green
        case .unknown:      Color.white
        }
    }

    // MARK: - Conversation panel

    private var conversationPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                // Last user message (dimmed)
                if !aiLayer.lastUserMessage.isEmpty {
                    Text("You: \(aiLayer.lastUserMessage)")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }

                // AI streaming text or last complete response
                let displayText = aiLayer.isStreaming
                    ? aiLayer.streamingText
                    : aiLayer.lastResponse

                if !displayText.isEmpty {
                    Text(displayText)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(6)
                        .animation(.easeInOut(duration: 0.06), value: displayText)
                }

                // Placeholder — shown only when there's no history yet
                if aiLayer.lastUserMessage.isEmpty && aiLayer.lastResponse.isEmpty {
                    Text(hotkeyManager.isMonitoring ? "Press ⌥ Space or tap mic to speak." : "Tap the mic to speak.")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.14))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.vertical, 4)
        }
        // Soft fade at top and bottom edges
        .mask(
            LinearGradient(
                colors:     [.clear, .black.opacity(0.9), .black.opacity(0.9), .clear],
                startPoint: .top,
                endPoint:   .bottom
            )
        )
    }

    // MARK: - Mic button

    private var micButton: some View {
        Button { handleMicTapped() } label: {
            ZStack {
                // Outer glow ring
                // — continuous mode: always-on ring (solid, brighter)
                // — single listen: standard listening ring
                if voiceSystem.isContinuousMode || voiceSystem.isListening {
                    Circle()
                        .stroke(
                            micAccentColor.opacity(voiceSystem.isContinuousMode ? 0.45 : 0.30),
                            lineWidth: voiceSystem.isContinuousMode ? 2.0 : 1.5
                        )
                        .frame(width: 58, height: 58)
                        // Second outer ring in continuous mode — signals "always on"
                    if voiceSystem.isContinuousMode {
                        Circle()
                            .stroke(micAccentColor.opacity(0.15), lineWidth: 1.0)
                            .frame(width: 68, height: 68)
                    }
                }

                // Core button
                Circle()
                    .fill(micButtonFill)
                    .frame(width: 44, height: 44)
                    .shadow(
                        color:  micAccentColor.opacity(voiceSystem.isListening || voiceSystem.isContinuousMode ? 0.55 : 0.18),
                        radius: voiceSystem.isListening || voiceSystem.isContinuousMode ? 14 : 6
                    )

                // Icon:
                //  • continuous mode + speaking  → waveform (barge-in hint)
                //  • continuous mode + listening → waveform
                //  • continuous mode + thinking  → stop.fill (tap to exit)
                //  • single listening             → waveform
                //  • idle                         → mic.fill
                let icon: String = {
                    if voiceSystem.isContinuousMode {
                        return voiceSystem.isListening || voiceSystem.isSpeaking
                            ? "waveform"
                            : "stop.fill"
                    }
                    return voiceSystem.isListening ? "waveform" : "mic.fill"
                }()

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(voiceSystem.isListening || voiceSystem.isContinuousMode ? 1.08 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: voiceSystem.isListening)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: voiceSystem.isContinuousMode)
        // In continuous mode the button is always tappable (tap = stop).
        // In single-turn mode, disable during thinking/speaking.
        .disabled(
            !voiceSystem.isContinuousMode &&
            (engine.pulseState == .thinking || engine.pulseState == .deepThinking || voiceSystem.isSpeaking)
        )
        .opacity(
            (!voiceSystem.isContinuousMode &&
             (engine.pulseState == .thinking || engine.pulseState == .deepThinking || voiceSystem.isSpeaking))
            ? 0.40 : 1.0
        )
    }

    private var micAccentColor: Color {
        switch engine.pulseState {
        case .listening:    Color(red: 0.35, green: 1.00, blue: 0.72)   // aqua
        case .thinking:     Color(red: 0.75, green: 0.45, blue: 1.00)   // purple
        case .deepThinking: Color(red: 0.88, green: 0.78, blue: 1.00)   // bright violet
        case .speaking:     Color(red: 1.00, green: 0.92, blue: 0.60)   // gold
        case .learning:     Color(red: 1.00, green: 0.85, blue: 0.20)   // warm gold
        default:            Color.white
        }
    }

    private var micButtonFill: some ShapeStyle {
        voiceSystem.isListening
            ? AnyShapeStyle(micAccentColor.opacity(0.22))
            : AnyShapeStyle(Color.white.opacity(0.10))
    }

    // MARK: - Conversation coordinator

    private func handleMicTapped() {

        // ── Continuous mode active: tap = stop everything ──────────────────
        if voiceSystem.isContinuousMode {
            voiceSystem.stopContinuousConversation()
            voiceSystem.stopSpeaking()
            voiceSystem.stopListening()
            engine.setState(.idle)
            conversationTask?.cancel()
            conversationTask = nil
            return
        }

        // ── Not in continuous mode: single-turn interrupt handling ──────────
        if voiceSystem.isListening  { voiceSystem.stopListening(); return }
        if voiceSystem.isSpeaking   { voiceSystem.stopSpeaking();  return }

        // ── Start continuous conversation mode ─────────────────────────────
        conversationTask?.cancel()
        conversationTask = Task { @MainActor in

            // Permissions (no-op after first grant, cached by TCC)
            guard await voiceSystem.requestPermissions() else {
                withAnimation { errorMessage = "Microphone or speech recognition permission denied." }
                return
            }

            // Signal learning system: user manually triggered a conversation
            companionEngine.recordManualTrigger()

            // Set initial visual state
            engine.setState(.listening)

            // Capture all dependencies as local constants so the handler closure
            // below captures value-typed references to the class instances,
            // not the SwiftUI struct's stored properties (which can be copied).
            let vs      = voiceSystem
            let ai      = aiLayer
            let viz     = engine
            let perc    = perception
            let acmon   = activityMonitor
            let auto    = automationEngine

            // ── Per-turn handler — called by VoiceSystem on every endpoint ──
            //
            // Runs on @MainActor. Does AI streaming + sentence-by-sentence TTS.
            // Errors are caught internally; the loop restarts listen() regardless.
            vs.startContinuousConversation { @MainActor transcript in

                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { viz.setState(.listening); return }

                // Gather perception context (screen OCR on user-initiated turns)
                viz.setState(.thinking)
                let screenCtx = await perc.gatherContext(
                    activity:      acmon,
                    captureScreen: perc.isScreenCaptureGranted
                )

                // ── Sentence-streaming TTS pipeline ──────────────────────────
                // First sentence fires ~200-300 ms after user stops speaking.
                // BUTLER speaks sentence 1 while Claude generates sentence 2.
                let sentenceStream = ai.sendStreaming(
                    trimmed,
                    context: acmon.context,
                    appName: acmon.frontmostAppName,
                    screenContext: screenCtx
                )

                var spokenAtLeastOne = false
                do {
                    for try await sentence in sentenceStream {
                        let clean = AutomationEngine.stripActions(from: sentence)
                        guard !clean.isEmpty else { continue }

                        if !spokenAtLeastOne {
                            viz.setState(.speaking)
                            spokenAtLeastOne = true
                        }
                        vs.queueSentence(clean)
                    }
                } catch {
                    NotificationCenter.default.post(
                        name: .butlerConversationError,
                        object: error.localizedDescription
                    )
                }

                // Wait for last sentence to finish (or barge-in resolves drainQueue early)
                await vs.drainQueue()

                // Run any BUTLER_DO automation commands from the complete response
                await auto.executeFromResponse(ai.lastResponse)

                // Back to listening — loop will call listen() again automatically
                if vs.isContinuousMode {
                    viz.setState(.listening)
                }
            }
        }
    }

    // MARK: - Haptic feedback

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    // MARK: - API Key setup sheet

    private var apiKeySetupSheet: some View {
        VStack(spacing: 20) {

            // Header
            VStack(spacing: 6) {
                Text("BUTLER")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .tracking(4)
                Text("Choose your AI provider and add an API key.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Provider picker
            VStack(alignment: .leading, spacing: 8) {
                Text("PROVIDER")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)

                Picker("Provider", selection: Binding(
                    get: { aiLayer.selectedProvider },
                    set: { aiLayer.selectedProvider = $0; apiKeyDraft = "" }
                )) {
                    ForEach(AIProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            // API key field — placeholder and link change with provider
            VStack(alignment: .leading, spacing: 6) {
                Text("API KEY")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)

                SecureField(aiLayer.selectedProvider.provider.apiKeyPlaceholder, text: $apiKeyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
            }

            Text("Keys are stored in the macOS Keychain — one per provider. Nothing leaves your machine except API requests.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Save & Start") {
                aiLayer.saveApiKey(apiKeyDraft)
                apiKeyDraft = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(apiKeyDraft.count < 20)

            Link(
                "Get a key → \(aiLayer.selectedProvider.provider.apiKeyURL.host ?? "")",
                destination: aiLayer.selectedProvider.provider.apiKeyURL
            )
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            Button("Skip for now") {
                aiLayer.skipSetup()
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(30)
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.15), value: aiLayer.selectedProvider)
    }

    // MARK: - Dev state controls (right-click → "Show State Controls" to reveal)

    private var testControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(VisualizationEngine.PulseState.allCases, id: \.self) { state in
                    stateButton(for: state)
                }
            }
            if engine.pulseState == .speaking {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.30))
                    Slider(
                        value: Binding(
                            get: { engine.amplitude },
                            set: { engine.setAmplitude($0) }
                        ),
                        in: 0 ... 1
                    )
                    .tint(.white.opacity(0.45))
                }
                .padding(.horizontal, 22)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: engine.pulseState)
    }

    private func stateButton(for state: VisualizationEngine.PulseState) -> some View {
        let isActive = engine.pulseState == state
        let label: String = switch state {
        case .idle:         "IDLE"
        case .listening:    "LISTEN"
        case .thinking:     "THINK"
        case .deepThinking: "DEEP"
        case .speaking:     "SPEAK"
        case .learning:     "LEARN"
        }
        return Button { engine.setState(state) } label: {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(isActive ? .white : .white.opacity(0.28))
                .tracking(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(isActive ? Color.white.opacity(0.13) : Color.clear)
                        .overlay {
                            Capsule().strokeBorder(
                                .white.opacity(isActive ? 0.18 : 0.07),
                                lineWidth: 0.5
                            )
                        }
                }
        }
        .buttonStyle(.plain)
    }

}

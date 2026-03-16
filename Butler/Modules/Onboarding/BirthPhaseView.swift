import SwiftUI

// MARK: - BirthPhaseView

/// Full-screen onboarding experience shown on first launch.
///
/// Presents the BUTLER birth sequence:
///   dark → system boot → digital awakening + voice selection →
///   voice received + first words → discovery scan → Q&A → declaration.
///
/// Layout (dark full-bleed):
///   ┌─────────────────────────────┐
///   │  [Skip]                     │  ← top-right, always visible
///   │                             │
///   │   ●●● Pulse orb (280pt) ●●● │  ← BirthOrbView phases 0–3, PulseWebView 4+
///   │                             │
///   │   [phase-specific content]  │  ← boot text / voice picker / question
///   │                             │
///   │   [Mic button]              │  ← glows during isListeningForAnswer
///   └─────────────────────────────┘
///
/// The orb swaps from `BirthOrbView` (SwiftUI Canvas, no JSC) to `PulseWebView`
/// (WebGL) only at `.discovery`. This prevents the PAC crash in WebKit's JIT
/// that fires when evaluateJavaScript is called rapidly during the boot phase.
struct BirthPhaseView: View {

    var coordinator: BirthPhaseCoordinator

    /// Observed directly so the orb responds to `visualEngine.setState()` calls.
    var engine: VisualizationEngine

    // MARK: - Orb state mapping

    /// Maps `coordinator.phase` to the standard state string consumed by
    /// the normal `window.butler.setState()` path. During birth-specific phases
    /// the birth overlay takes visual control, so we park the normal state at
    /// `"idle"` to keep the underlying orb alive but neutral.
    private var birthOrbState: String {
        switch coordinator.phase {
        case .dormant:          return "idle"
        case .booting:          return "idle"
        case .digitalAwakening: return "listening"
        case .voiceReceived:    return "speaking"
        case .discovery:        return coordinator.isSpeakingNow ? "speaking" : "thinking"
        case .questioning:      return coordinator.isSpeakingNow ? "speaking" : "listening"
        case .declaring:        return coordinator.isSpeakingNow ? "speaking" : "idle"
        case .complete:         return "idle"
        }
    }

    /// Maps `coordinator.phase` to the birth-mode phase string sent to
    /// `window.butler.setBirthMode(phase, isSpeaking)` in the JS layer.
    /// Returns `nil` after the birth sequence ends to disable birth mode.
    private var birthWebGLPhase: String? {
        switch coordinator.phase {
        case .dormant:          return "birth_dormant"
        case .booting:          return "birth_booting"
        case .digitalAwakening: return "birth_awakening"
        case .voiceReceived:    return "birth_received"
        case .discovery, .questioning, .declaring:
            // Orb is fully formed — no birth-specific overlay, use normal states
            return nil
        case .complete:         return nil
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Orb — switches between two implementations based on phase.
                //
                // Phases 0–3 (dormant → voiceReceived): BirthOrbView — pure SwiftUI
                // Canvas, no JavaScript, no JSC JIT. Avoids the PAC crash in
                // WebKit's lsl::MemoryManager::writeProtect that fires when
                // evaluateJavaScript is called rapidly during the typewriter boot phase.
                //
                // Phase 4+ (discovery → complete): PulseWebView — full WebGL orb,
                // loaded only after the boot storm is over so JSC has stable conditions.
                orbView
                .frame(width: 280, height: 280)
                .opacity(coordinator.phase == .dormant ? 0 : 1)
                .animation(.easeIn(duration: 2.5), value: coordinator.phase == .dormant)

                Spacer(minLength: 24)

                // Phase-specific content area
                phaseContent
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 32)

                Spacer(minLength: 32)

                // Mic indicator — only visible during Q&A
                if coordinator.phase == .questioning {
                    micIndicator
                        .padding(.bottom, 40)
                } else {
                    Spacer(minLength: 56)
                }
            }
        }
        // Skip button — top right, always accessible
        .overlay(alignment: .topTrailing) {
            Button {
                coordinator.skip()
            } label: {
                Text("Skip")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .frame(minWidth: 480, minHeight: 600)
        .onAppear {
            coordinator.begin()
        }
    }

    // MARK: - Orb view selector

    /// Returns the correct orb view for the current phase.
    /// Early birth phases use BirthOrbView (SwiftUI Canvas, no JSC).
    /// Once the birth sequence stabilises at .discovery, PulseWebView is safe to create.
    @ViewBuilder
    private var orbView: some View {
        switch coordinator.phase {
        case .dormant, .booting, .digitalAwakening, .voiceReceived:
            // Birth orb visual placeholder — awaiting new design
            Color.clear

        default:
            PulseWebView(
                state:      birthOrbState,
                amplitude:  engine.amplitude,
                birthPhase: birthWebGLPhase,
                isSpeaking: coordinator.isSpeakingNow
            )
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private var phaseContent: some View {
        switch coordinator.phase {

        case .dormant:
            Color.clear.frame(height: 120)

        case .booting:
            bootTextView

        case .digitalAwakening:
            digitalAwakeningView
                .transition(.opacity.animation(.easeIn(duration: 0.6)))

        case .voiceReceived, .discovery, .declaring:
            speechSubtitleView

        case .questioning:
            questionView

        case .complete:
            Color.clear.frame(height: 120)
        }
    }

    // MARK: - Boot text view

    private var bootTextView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(coordinator.bootText)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.35, green: 1.00, blue: 0.72).opacity(0.85))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.none, value: coordinator.bootText)

            BlinkingCursor()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Digital awakening view (Phase 2)

    /// Shows the "awaiting voice" status line and the inline voice picker.
    private var digitalAwakeningView: some View {
        VStack(spacing: 14) {
            // Glitchy status line
            Text(coordinator.displayText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color.cyan.opacity(0.70))
                .tracking(1.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // Voice selection card
            VoiceSelectionView(
                selectedVoiceIdentifier: Binding(
                    get: { coordinator.selectedVoiceIdentifier },
                    set: { coordinator.selectedVoiceIdentifier = $0 }
                ),
                onVoiceSelected: { coordinator.voiceWasSelected() }
            )
        }
    }

    // MARK: - Speech subtitle view

    private var speechSubtitleView: some View {
        Text(coordinator.butlerSpeechLine)
            .font(.system(size: 14, weight: .light))
            .italic()
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            .animation(.easeInOut(duration: 0.20), value: coordinator.butlerSpeechLine)
    }

    // MARK: - Question view

    private var questionView: some View {
        VStack(spacing: 20) {
            Text("QUESTION \(coordinator.questionIndex + 1) OF \(BirthPhaseCoordinator.questions.count)")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(2)

            Text(coordinator.questionText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.90))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.20), value: coordinator.questionText)

            Text(coordinator.isListeningForAnswer ? "Listening..." : "")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.35, green: 1.00, blue: 0.72).opacity(0.70))
                .animation(.easeInOut(duration: 0.18), value: coordinator.isListeningForAnswer)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Mic indicator

    private var micIndicator: some View {
        ZStack {
            if coordinator.isListeningForAnswer {
                Circle()
                    .stroke(
                        Color(red: 0.35, green: 1.00, blue: 0.72).opacity(0.35),
                        lineWidth: 1.5
                    )
                    .frame(width: 64, height: 64)
            }

            Circle()
                .fill(
                    coordinator.isListeningForAnswer
                    ? Color(red: 0.35, green: 1.00, blue: 0.72).opacity(0.20)
                    : Color.white.opacity(0.08)
                )
                .frame(width: 48, height: 48)
                .shadow(
                    color: Color(red: 0.35, green: 1.00, blue: 0.72).opacity(
                        coordinator.isListeningForAnswer ? 0.55 : 0.10
                    ),
                    radius: coordinator.isListeningForAnswer ? 18 : 4
                )

            Image(systemName: coordinator.isListeningForAnswer ? "waveform" : "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(coordinator.isListeningForAnswer ? 1.0 : 0.50))
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: coordinator.isListeningForAnswer)
    }
}

// MARK: - BlinkingCursor

/// A monospaced blinking block cursor used in the boot text view.
private struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Text("_")
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(Color(red: 0.35, green: 1.00, blue: 0.72).opacity(visible ? 0.85 : 0.0))
            .onAppear {
                Task { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(550))
                        visible.toggle()
                    }
                }
            }
    }
}

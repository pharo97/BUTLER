import Observation

/// The central state machine for the Glass Chamber visualization.
///
/// All mutations are isolated to `@MainActor` so SwiftUI views can safely
/// observe them without crossing concurrency boundaries.
@MainActor
@Observable
final class VisualizationEngine {

    // MARK: - Pulse states

    enum PulseState: String, CaseIterable, Hashable {
        case idle         = "idle"
        case listening    = "listening"
        case thinking     = "thinking"
        case deepThinking = "deepThinking"  // Long inference — denser neural overlay
        case speaking     = "speaking"
        case learning     = "learning"      // Post-feedback — gold growth pathways
    }

    // MARK: - Observed properties
    // Read-only from outside; mutated only via the control methods below.

    private(set) var pulseState: PulseState = .idle
    private(set) var amplitude:  Double     = 0.0
    private(set) var statusText: String     = "Ready"

    /// Optional callback fired on every state transition.
    /// Used by MenuBarManager (AppKit) to update the menu bar icon without
    /// requiring SwiftUI observation in a non-View context.
    var onStateChange: ((PulseState) -> Void)?

    // MARK: - Control

    /// Transition to a new pulse state.
    func setState(_ state: PulseState) {
        pulseState = state
        statusText = switch state {
        case .idle:         "Ready"
        case .listening:    "Listening…"
        case .thinking:     "Thinking…"
        case .deepThinking: "Processing…"
        case .speaking:     "Speaking"
        case .learning:     "Learning…"
        }
        // Reset amplitude when leaving the speaking state.
        if state != .speaking {
            amplitude = 0.0
        }
        onStateChange?(state)
    }

    /// Update the audio amplitude (0.0 – 1.0) driving the speaking animation.
    /// Called at audio-tap rate (~60 Hz) during TTS playback.
    func setAmplitude(_ value: Double) {
        amplitude = max(0.0, min(1.0, value))
    }
}

import SwiftUI
import AVFoundation

// MARK: - VoiceSelectionView

/// Inline voice picker used during the birth-phase digital awakening.
///
/// Lists all installed `AVSpeechSynthesisVoice` instances across all languages, sorted premium-first.
/// The user can preview any voice before committing. Selecting a voice:
///   1. Sets `selectedVoiceIdentifier` binding
///   2. Writes to UserDefaults under two keys consumed by the whole app:
///      - `butler.tts.voiceIdentifier` — the canonical cross-app key
///      - `butler.selectedVoiceIdentifier.v1` — VoiceProfileManager's persistence key
///   3. Calls `onVoiceSelected()` so the coordinator can advance the phase
///
/// This view is intentionally self-contained — no dependency on VoiceProfileManager —
/// so it can be used before AppDelegate has finished wiring all modules.
struct VoiceSelectionView: View {

    @Binding var selectedVoiceIdentifier: String?
    var onVoiceSelected: () -> Void

    // MARK: - Voice list

    /// All installed voices sorted: Premium → Enhanced → Standard, then by language, then name.
    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { a, b in
                let aRank = qualityRank(a.quality)
                let bRank = qualityRank(b.quality)
                if aRank != bRank { return aRank > bRank }
                if a.language != b.language { return a.language < b.language }
                return a.name < b.name
            }
    }

    // MARK: - Preview synth

    /// Dedicated synthesizer so previewing never touches VoiceSystem's pipeline.
    @State private var previewSynth = AVSpeechSynthesizer()
    @State private var previewingID: String? = nil

    private let previewText = "Hello. I am your companion. I can see what you're working on."

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Text("SELECT A VOICE  —  \(voices.count) INSTALLED")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .tracking(3)
                .padding(.horizontal, 4)

            // Voice list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(voices, id: \.identifier) { voice in
                        voiceRow(voice)
                    }
                }
            }
            .frame(maxHeight: 248)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
        )
        .onDisappear {
            // Stop any in-progress preview so the synthesizer is silent when
            // the voice-received phase begins. Without this, the preview voice
            // overlaps BUTLER's first spoken words.
            previewSynth.stopSpeaking(at: .immediate)
            previewingID = nil
        }
    }

    // MARK: - Voice row

    @ViewBuilder
    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        let isSelected  = selectedVoiceIdentifier == voice.identifier
        let isPreviewing = previewingID == voice.identifier

        HStack(spacing: 8) {
            // Name + quality tags
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    // Language region label
                    if let region = regionLabel(for: voice.language) {
                        Text(region)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.38))
                    }
                    qualityBadge(voice.quality)
                }
            }

            Spacer(minLength: 4)

            // Preview and Select use .onTapGesture with Task { @MainActor in } bodies.
            //
            // On macOS 26 beta (Swift 6.2.3 + macOS Tahoe 25C56), SwiftUI's action
            // dispatch pipeline calls `swift_task_isCurrentExecutorWithFlagsImpl` on
            // the main actor executor object, which has an invalid isa pointer in
            // this OS/runtime combination. Any closure that inherits @MainActor
            // isolation from its enclosing View will crash when SwiftUI calls it
            // during a layout/update pass from an AppKit RunLoop callback (no Task).
            //
            // Wrapping the action body in `Task { @MainActor in }` makes the closure
            // itself nonisolated (no executor check at entry), while the actual work
            // still runs on the main actor — after Swift concurrency has been
            // properly initialized by the Task infrastructure.
            Image(systemName: isPreviewing ? "stop.circle" : "speaker.wave.2")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(isPreviewing ? .cyan.opacity(0.9) : .white.opacity(0.55))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { @MainActor in togglePreview(voice) }
                }

            Text(isSelected ? "SELECTED" : "SELECT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.13))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { @MainActor in selectVoice(voice) }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.white.opacity(0.07) : Color.white.opacity(0.025))
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Quality badge

    @ViewBuilder
    private func qualityBadge(_ quality: AVSpeechSynthesisVoiceQuality) -> some View {
        switch quality {
        case .premium:
            Text("PREMIUM")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.35, green: 1.00, blue: 0.72).opacity(0.9))
        case .enhanced:
            Text("ENHANCED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.cyan.opacity(0.75))
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func togglePreview(_ voice: AVSpeechSynthesisVoice) {
        if previewingID == voice.identifier {
            previewSynth.stopSpeaking(at: .immediate)
            previewingID = nil
        } else {
            previewSynth.stopSpeaking(at: .immediate)
            previewingID = voice.identifier
            let utterance        = AVSpeechUtterance(string: previewText)
            utterance.voice      = voice
            utterance.rate       = 0.50
            utterance.volume     = 0.9
            previewSynth.speak(utterance)
            // Clear previewingID after estimated playback duration
            let estimatedDuration = Double(previewText.count) * 0.065
            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
                if previewingID == voice.identifier {
                    previewingID = nil
                }
            }
        }
    }

    private func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        previewSynth.stopSpeaking(at: .immediate)
        previewingID = nil
        selectedVoiceIdentifier = voice.identifier

        // Write to both keys: canonical (used by BirthPhaseCoordinator + VoiceSystem patch)
        // and VoiceProfileManager's key (keeps Settings in sync after onboarding)
        UserDefaults.standard.set(voice.identifier, forKey: "butler.tts.voiceIdentifier")
        UserDefaults.standard.set(voice.identifier, forKey: "butler.selectedVoiceIdentifier.v1")
        UserDefaults.standard.set(voice.name,       forKey: "butler.tts.voiceName")

        onVoiceSelected()
    }

    // MARK: - Helpers

    private func qualityRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium:  return 2
        case .enhanced: return 1
        default:        return 0
        }
    }

    private func regionLabel(for language: String) -> String? {
        let locale = Locale(identifier: language)
        guard let region = locale.region?.identifier else { return nil }
        let name = Locale.current.localizedString(forRegionCode: region)
        return name?.isEmpty == false ? name : nil
    }
}

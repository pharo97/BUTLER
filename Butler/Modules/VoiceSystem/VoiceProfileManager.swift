import AVFoundation
import Foundation

// MARK: - VoiceGender

enum VoiceGender: String, CaseIterable, Identifiable {
    case female = "Female"
    case male   = "Male"
    case other  = "Other"

    var id: String { rawValue }

    init(_ avGender: AVSpeechSynthesisVoiceGender) {
        switch avGender {
        case .female: self = .female
        case .male:   self = .male
        default:      self = .other
        }
    }
}

// MARK: - VoiceOption

struct VoiceOption: Identifiable, Hashable {
    let identifier:   String
    let name:         String
    let languageCode: String
    let gender:       VoiceGender
    let quality:      AVSpeechSynthesisVoiceQuality

    var id: String { identifier }

    var qualityLabel: String {
        switch quality {
        case .premium:  return "Premium"
        case .enhanced: return "Enhanced"
        default:        return "Standard"
        }
    }

    /// Numeric rank for sorting (higher = better).
    var qualityRank: Int {
        switch quality {
        case .premium:  return 2
        case .enhanced: return 1
        default:        return 0
        }
    }

    /// Friendly region label derived from language code (e.g. "en-AU" → "Australia").
    var regionLabel: String {
        let locale = Locale(identifier: languageCode)
        guard let region = locale.region?.identifier else { return "" }
        return Locale.current.localizedString(forRegionCode: region) ?? ""
    }

    func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
    static func == (lhs: VoiceOption, rhs: VoiceOption) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

// MARK: - VoiceProfileManager

/// Manages BUTLER's TTS voice selection.
///
/// • Lists all installed English `AVSpeechSynthesisVoice` instances, grouped by gender
/// • Persists the user's choice to UserDefaults
/// • Provides a live preview synthesizer so the user can audition voices
///   without touching VoiceSystem's main synthesizer
///
/// Future: the selected voice will evolve based on LearningSystem feedback —
/// e.g. slower rate when BUTLER detects the user is tired or overwhelmed.
@MainActor
@Observable
final class VoiceProfileManager {

    // MARK: - Persistence key

    private static let defaultsKey = "butler.selectedVoiceIdentifier.v1"

    // MARK: - State

    private(set) var voices: [VoiceOption] = []

    var selectedVoiceIdentifier: String = "" {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: Self.defaultsKey)
        }
    }

    /// Rate multiplier [0.3 – 0.7]. Default 0.50. Exposed for future UX personalisation.
    var speakingRate: Float = 0.50 {
        didSet {
            let clamped = max(0.3, min(0.7, speakingRate))
            if speakingRate != clamped { speakingRate = clamped }
            UserDefaults.standard.set(speakingRate, forKey: "butler.speakingRate.v1")
        }
    }

    // MARK: - Derived

    var selectedVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
    }

    /// Voices grouped by gender in display order: Female → Male → Other.
    var voicesByGender: [(gender: VoiceGender, voices: [VoiceOption])] {
        VoiceGender.allCases.compactMap { gender in
            let group = voices.filter { $0.gender == gender }
            return group.isEmpty ? nil : (gender, group)
        }
    }

    // MARK: - Preview synthesizer (independent of VoiceSystem)

    private let previewSynth = AVSpeechSynthesizer()
    private static let previewPhrase = "Hey, I'm BUTLER. Good to have you here."

    // MARK: - Init

    init() {
        loadVoices()
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        speakingRate = UserDefaults.standard.float(forKey: "butler.speakingRate.v1")
        if speakingRate == 0 { speakingRate = 0.50 }

        // Validate saved identifier is still installed; fall back to best default
        if !saved.isEmpty, voices.contains(where: { $0.identifier == saved }) {
            selectedVoiceIdentifier = saved
        } else {
            selectedVoiceIdentifier = bestDefaultIdentifier()
        }
    }

    // MARK: - Voice loading

    private func loadVoices() {
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { v in
                VoiceOption(
                    identifier:   v.identifier,
                    name:         v.name,
                    languageCode: v.language,
                    gender:       VoiceGender(v.gender),
                    quality:      v.quality
                )
            }
            .sorted { lhs, rhs in
                if lhs.qualityRank != rhs.qualityRank { return lhs.qualityRank > rhs.qualityRank }
                return lhs.name < rhs.name
            }
    }

    private func bestDefaultIdentifier() -> String {
        // Prefer: Premium female → Enhanced female → Enhanced male → anything
        let pick = voices.first { $0.quality == .premium  && $0.gender == .female }
            ?? voices.first { $0.quality == .enhanced && $0.gender == .female }
            ?? voices.first { $0.quality == .enhanced && $0.gender == .male   }
            ?? voices.first
        return pick?.identifier ?? ""
    }

    // MARK: - Preview

    func previewVoice(_ option: VoiceOption) {
        previewSynth.stopSpeaking(at: .immediate)
        let utterance        = AVSpeechUtterance(string: Self.previewPhrase)
        utterance.voice      = AVSpeechSynthesisVoice(identifier: option.identifier)
        utterance.rate       = speakingRate
        utterance.volume     = 0.9
        previewSynth.speak(utterance)
    }

    func stopPreview() {
        previewSynth.stopSpeaking(at: .immediate)
    }
}

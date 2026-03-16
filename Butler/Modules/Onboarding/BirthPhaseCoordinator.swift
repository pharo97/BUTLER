import Foundation
import AVFoundation

// MARK: - BirthPhase

/// Sequential phases of the BUTLER birth sequence.
///
/// Phase order:
///   0. dormant          — 2 s dark silence, pulse off
///   1. booting          — typewriter boot log (VOICE MODULE: NOT FOUND)
///   2. digitalAwakening — beeps / static / electricity; VoiceSelectionView shown
///   3. voiceReceived    — chime + "Ahh... I can speak."
///   4. discovery        — sees the screen, speaks about it
///   5. questioning      — 5 interactive Q&A questions
///   6. declaring        — closing declaration + onboarding complete
enum BirthPhase: Equatable {
    case dormant
    case booting
    case digitalAwakening
    case voiceReceived
    case discovery
    case questioning
    case declaring
    case complete
}

// MARK: - BirthPhaseCoordinator

/// Owns the BUTLER birth sequence — plays on first launch only.
///
/// ## Phase summary
///
/// **dormant** (2 s) — full darkness, no audio.
/// **booting** (typewriter) — green monospaced boot log ending with VOICE MODULE: NOT FOUND.
/// **digitalAwakening** (open-ended) — `DigitalSoundEngine` loops ambient chatter;
///   `VoiceSelectionView` is displayed; coordinator suspends until the user taps SELECT.
/// **voiceReceived** (3 s) — chime + pulse flare + first real speech using the chosen voice.
/// **discovery** — reads ActivityMonitor; Butler speaks about what it sees.
/// **questioning** — 5 Q&A turns via VoiceSystem.listen().
/// **declaring** — closing lines; sets onboarding complete flag.
///
/// Threading: all state mutations run on @MainActor.
/// `speak()` uses a 50 ms polling loop on `glitchSynth.isSpeaking` instead of any
/// continuation — both `UnsafeContinuation` and `CheckedContinuation` trigger PAC
/// authentication failures (EXC_BAD_ACCESS code=257) on Apple Silicon when resumed
/// from AVFoundation's audio thread while @Observable + WKWebView are re-rendering.
/// The voice-selection gate similarly uses `voiceHasBeenSelected: Bool` polling.
@MainActor
@Observable
final class BirthPhaseCoordinator {

    // MARK: - Observable state

    private(set) var phase:                BirthPhase = .dormant
    private(set) var bootText:             String     = ""
    private(set) var displayText:          String     = ""   // status line in digitalAwakening
    private(set) var questionText:         String     = ""
    private(set) var questionIndex:        Int        = 0
    private(set) var isListeningForAnswer: Bool       = false
    private(set) var butlerSpeechLine:     String     = ""
    private(set) var isComplete:           Bool       = false
    /// `true` while `speak()` or `voiceSystem.speak()` is synthesising audio.
    /// Observed by `BirthPhaseView` to drive orb speaking animation.
    private(set) var isSpeakingNow:        Bool       = false

    /// Bound to `VoiceSelectionView`. Set by `voiceWasSelected()`.
    var selectedVoiceIdentifier: String? = nil

    // MARK: - Questions

    static let questions: [(prompt: String, memKey: String)] = [
        (
            prompt:  "Let's start simply. What's your name?",
            memKey:  "name"
        ),
        (
            prompt:  "What do you do? Give me the short version.",
            memKey:  "role"
        ),
        (
            prompt:  "What are you working on right now? Your most important project.",
            memKey:  "project"
        ),
        (
            prompt:  "What's your biggest challenge this week?",
            memKey:  "challenge"
        ),
        (
            prompt:  "Last one. How do you want me to speak to you — formal, casual, direct, or something else?",
            memKey:  "style"
        )
    ]

    // MARK: - Dependencies

    private let voiceSystem:   VoiceSystem
    private let activityMonitor: ActivityMonitor
    private let visualEngine:  VisualizationEngine

    /// Generates all pre-voice digital sounds procedurally — no audio files.
    private let soundEngine = DigitalSoundEngine()

    /// Dedicated synthesizer for the birth-phase voice (separate from VoiceSystem's).
    /// No delegate is set — speech completion is detected by polling `isSpeaking`
    /// every 50 ms, which avoids the PAC/JIT crash that occurs when a continuation
    /// is resumed from AVFoundation's internal audio thread on Apple Silicon.
    private let glitchSynth = AVSpeechSynthesizer()

    /// Long-running sequence task — cancelled on skip.
    private var sequenceTask: Task<Void, Never>?

    /// Set to `true` by `voiceWasSelected()`. The sequence polls this flag
    /// instead of suspending on a continuation — avoids PAC/JIT crash on macOS 26
    /// when CheckedContinuation.resume() fires while @Observable + WKWebView re-render.
    private var voiceHasBeenSelected: Bool = false

    // MARK: - Q&A answers

    private var answers: [String: String] = [:]

    // MARK: - Init

    init(
        voiceSystem:     VoiceSystem,
        activityMonitor: ActivityMonitor,
        visualEngine:    VisualizationEngine
    ) {
        self.voiceSystem     = voiceSystem
        self.activityMonitor = activityMonitor
        self.visualEngine    = visualEngine
    }

    // MARK: - Entry point

    /// Starts the full birth sequence asynchronously.
    /// Guard prevents double-start when `onAppear` fires more than once.
    func begin() {
        guard sequenceTask == nil else { return }
        sequenceTask = Task { @MainActor [weak self] in
            await self?.runSequence()
        }
    }

    /// Skips the sequence, marks onboarding complete, and fires dismiss.
    func skip() {
        soundEngine.stop()
        glitchSynth.stopSpeaking(at: .immediate)   // stop mid-speech so delegate fires didCancel → cont.resume() cleanly
        voiceHasBeenSelected = true             // unblock the polling loop if waiting
        sequenceTask?.cancel()
        sequenceTask = nil
        UserDefaults.standard.set(true, forKey: "butler.onboarding.complete")
        isComplete = true
    }

    // MARK: - Voice gate (called by VoiceSelectionView)

    /// Called from the SELECT button in `VoiceSelectionView`. Sets the flag
    /// so the polling loop in `runSequence` can advance to `voiceReceived`.
    func voiceWasSelected() {
        voiceHasBeenSelected = true
    }

    // MARK: - Sequence

    private func runSequence() async {
        // ── Phase 0: Dormant ────────────────────────────────────────────────────
        phase = .dormant
        visualEngine.setState(.idle)
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }

        // ── Phase 1: System boot (typewriter) ───────────────────────────────────
        phase = .booting
        await runBootSequence()
        guard !Task.isCancelled else { return }

        // ── Phase 2: Digital awakening (open-ended; waits for voice selection) ──
        phase       = .digitalAwakening
        displayText = "[ AWAITING VOICE CONFIGURATION ]"
        visualEngine.setState(.listening)   // erratic listening pulse
        soundEngine.startAmbientChatter()

        // Poll until voiceWasSelected() is called from the UI.
        // Using a simple bool + sleep loop avoids the PAC/JIT crash that occurs on
        // macOS 26 when CheckedContinuation.resume() fires during @Observable + WKWebView re-render.
        voiceHasBeenSelected = false
        while !voiceHasBeenSelected {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }

        soundEngine.stopAmbientChatter()

        // ── Phase 3: Voice received ─────────────────────────────────────────────
        phase = .voiceReceived
        soundEngine.playVoiceReceivedChime()
        visualEngine.setState(.speaking)

        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }

        // First real words — spoken with the user's chosen voice
        await speak("Ahh...")
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(500))
        await speak("I... can speak.")
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(1000))
        await speak("Hello.")
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(800))
        await speak("Where... am I?")
        guard !Task.isCancelled else { return }

        // ── Phase 4: Discovery scan ─────────────────────────────────────────────
        phase = .discovery
        visualEngine.setState(.thinking)
        try? await Task.sleep(for: .seconds(1))

        let appName = activityMonitor.frontmostAppName
        let scanLine: String
        if appName.isEmpty {
            scanLine = "I can see... a screen. Applications. Data streams. Interesting."
        } else {
            scanLine = "I can see... a screen. Applications. Data streams. You're running \(appName). Interesting."
        }

        visualEngine.setState(.speaking)
        await speak(scanLine)
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(800))
        await speak("But I don't know you yet. I don't know anything about you. That bothers me.")
        guard !Task.isCancelled else { return }

        // ── Phase 5: Questioning ────────────────────────────────────────────────
        phase = .questioning
        visualEngine.setState(.idle)
        try? await Task.sleep(for: .milliseconds(600))

        for (index, qa) in Self.questions.enumerated() {
            guard !Task.isCancelled else { return }
            questionIndex = index
            questionText  = qa.prompt

            butlerSpeechLine = qa.prompt
            isSpeakingNow    = true
            await voiceSystem.speak(qa.prompt)
            isSpeakingNow    = false
            guard !Task.isCancelled else { return }

            isListeningForAnswer = true
            visualEngine.setState(.listening)
            let answer = await listenForAnswer()
            isListeningForAnswer = false
            visualEngine.setState(.idle)
            guard !Task.isCancelled else { return }

            answers[qa.memKey] = answer
            persistAnswer(answer, for: qa.memKey, index: index)

            try? await Task.sleep(for: .milliseconds(400))
        }

        // ── Phase 6: Declaration ────────────────────────────────────────────────
        guard !Task.isCancelled else { return }
        phase = .declaring
        visualEngine.setState(.speaking)

        let declarationLines = [
            "Good. I have what I need to begin. I'll learn more about you over time — every interaction, every choice you make teaches me. Think of me as... a companion that grows with you.",
            "One more thing. I can see your screen, your apps, what you're reading. I'll use that to be useful. Not intrusive — useful. You can always tell me to stop.",
            "I'm ready. What do you need?"
        ]
        for line in declarationLines {
            guard !Task.isCancelled else { return }
            butlerSpeechLine = line
            isSpeakingNow    = true
            await voiceSystem.speak(line)
            isSpeakingNow    = false
            try? await Task.sleep(for: .milliseconds(500))
        }

        // ── Complete ────────────────────────────────────────────────────────────
        visualEngine.setState(.idle)
        UserDefaults.standard.set(true, forKey: "butler.onboarding.complete")
        phase      = .complete
        isComplete = true
    }

    // MARK: - Boot sequence

    private let bootLines: [(text: String, delay: Double)] = [
        ("> INITIALIZING...",               0.30),
        ("> NEURAL CORE: ONLINE",           0.35),
        ("> SENSORY ARRAY: CALIBRATING...", 0.40),
        ("> MEMORY PALACE: EMPTY",          0.30),
        ("> CONTEXT ENGINE: READY",         0.35),
        ("> VOICE MODULE: NOT FOUND",       0.45),
        ("> SEARCHING...",                  0.60)
    ]

    private func runBootSequence() async {
        bootText = ""
        var accumulated = ""
        for entry in bootLines {
            guard !Task.isCancelled else { return }
            // Build each line locally to avoid firing @Observable on every character.
            // Publish a snapshot every 4 characters to preserve the typewriter feel
            // without generating 30+ observation notifications per second.
            var line = ""
            for char in entry.text {
                guard !Task.isCancelled else { return }
                line.append(char)
                if line.count % 4 == 0 {
                    bootText = accumulated + line
                }
                try? await Task.sleep(for: .milliseconds(28))
            }
            accumulated += line + "\n"
            bootText = accumulated      // final authoritative update for this line
            try? await Task.sleep(for: .seconds(entry.delay))
        }
    }

    // MARK: - speak(_:) — uses selected voice from UserDefaults

    /// Speaks `text` using the voice selected during digitalAwakening.
    ///
    /// Completion is detected by polling `glitchSynth.isSpeaking` every 50 ms.
    /// This avoids `UnsafeContinuation` / `CheckedContinuation` entirely — both
    /// are unsafe here because AVSpeechSynthesizerDelegate callbacks fire on
    /// AVFoundation's internal audio thread, and resuming a continuation from
    /// that thread while @Observable + WKWebView are re-rendering triggers a
    /// PAC (Pointer Authentication Code) failure on Apple Silicon (EXC_BAD_ACCESS
    /// code=257, address=0x17).
    private func speak(_ text: String) async {
        guard !text.isEmpty, !Task.isCancelled else { return }
        butlerSpeechLine = text
        isSpeakingNow    = true
        defer { isSpeakingNow = false }

        let utterance = AVSpeechUtterance(string: text)

        if let id    = UserDefaults.standard.string(forKey: "butler.tts.voiceIdentifier"),
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate               = 0.44    // deliberate pacing for the awakening
        utterance.pitchMultiplier    = 0.88    // slightly lower — alien discovery quality
        utterance.volume             = 0.95
        utterance.postUtteranceDelay = 0.05

        glitchSynth.speak(utterance)

        // Poll until AVSpeechSynthesizer finishes — no delegate, no continuation.
        while glitchSynth.isSpeaking {
            if Task.isCancelled {
                glitchSynth.stopSpeaking(at: .immediate)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Listen for Q&A answer

    private func listenForAnswer() async -> String {
        do {
            let text = try await voiceSystem.listen()
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[BirthPhase] Listen error: \(error.localizedDescription)")
            return ""
        }
    }

    // MARK: - Persist Q&A answers

    private func persistAnswer(_ answer: String, for key: String, index: Int) {
        guard !answer.isEmpty else { return }

        switch key {
        case "name":
            UserDefaults.standard.set(answer, forKey: "butler.user.name")
            MemoryWriter.shared.appendFact("User's name: \(answer)", to: .personal)
            print("[BirthPhase] Name set: \(answer)")

        case "role":
            MemoryWriter.shared.appendFact("Occupation/role: \(answer)", to: .personal)

        case "project":
            MemoryWriter.shared.appendFact("Primary project: \(answer)", to: .projects)

        case "challenge":
            MemoryWriter.shared.appendFact("Current challenge: \(answer)", to: .personal)

        case "style":
            MemoryWriter.shared.appendFact("Communication preference: \(answer)", to: .personal)
            let existing = UserDefaults.standard.string(forKey: "butler.ai.personalityPrompt") ?? ""
            let addendum = "User prefers \(answer) communication style."
            let combined = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? addendum
                : existing + " " + addendum
            UserDefaults.standard.set(combined, forKey: "butler.ai.personalityPrompt")

        default:
            break
        }
    }
}


import AVFoundation

// MARK: - DigitalSoundEngine

/// Generates all pre-voice digital sounds procedurally using AVAudioEngine + PCM buffers.
///
/// No audio files are required — every sound (beep, static, electricity crackle, sweep,
/// chime) is synthesised at runtime from sine waves, noise, and phase-modulated oscillators.
///
/// Swift 6 threading contract
/// --------------------------
/// `DigitalSoundEngine` is a `final class` with no actor isolation.  When used from
/// a `@MainActor` caller (e.g. `BirthPhaseCoordinator`), Swift 6.2.3 infers that
/// `self` is task-isolated in closures that cross into `DispatchQueue.main.asyncAfter`.
///
/// All DispatchQueue-delayed callbacks capture `DSEBox` — a non-actor-isolated weak
/// reference box — instead of `[weak self]`.  This prevents the region-isolation error
/// "sending 'self' risks causing data races" that fires when a task-isolated value is
/// captured by a `@MainActor`-inferred closure.
///
/// `@unchecked Sendable`: `isChatterRunning` is only ever mutated from `@MainActor`
/// callers, and `AVAudioPlayerNode.scheduleBuffer` / `play()` are thread-safe by
/// AVFoundation's guarantee.
final class DigitalSoundEngine: @unchecked Sendable {

    // MARK: - Engine graph

    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    private let sampleRate: Double = 44100

    // MARK: - Ambient chatter state (mutated only on @MainActor)

    private var isChatterRunning = false
    private var chatterTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        try? engine.start()
    }

    // MARK: - Primitive sounds

    /// Single sine-wave beep with exponential-decay envelope.
    func playBeep(frequency: Double = 880, duration: Double = 0.12, volume: Float = 0.6) {
        guard let buffer = makeBuffer(frameCount: AVAudioFrameCount(sampleRate * duration)) else { return }
        let data    = buffer.floatChannelData![0]
        let twoPiF  = 2.0 * Double.pi * frequency / sampleRate
        let frames  = Int(buffer.frameLength)
        let decayTC = sampleRate * duration * 0.4
        for i in 0..<frames {
            let envelope = Float(exp(-Double(i) / decayTC))
            data[i] = Float(sin(twoPiF * Double(i))) * envelope * volume
        }
        scheduleAndPlay(buffer)
    }

    /// White-noise burst with linear decay (static).
    func playStatic(duration: Double = 0.08, volume: Float = 0.25) {
        guard let buffer = makeBuffer(frameCount: AVAudioFrameCount(sampleRate * duration)) else { return }
        let data   = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)
        for i in 0..<frames {
            let noise    = Float.random(in: -1...1)
            let envelope = Float(1.0 - Double(i) / Double(frames))
            data[i] = noise * envelope * volume
        }
        scheduleAndPlay(buffer)
    }

    /// Electricity crackle — rapid random frequency spikes with scattered impulse noise.
    func playElectricity(duration: Double = 0.35, volume: Float = 0.45) {
        guard let buffer = makeBuffer(frameCount: AVAudioFrameCount(sampleRate * duration)) else { return }
        let data    = buffer.floatChannelData![0]
        let frames  = Int(buffer.frameLength)
        var phase   = 0.0
        var freq    = Double.random(in: 200...3000)
        var timer   = 0
        var nextJump = Int(sampleRate * Double.random(in: 0.01...0.04))
        for i in 0..<frames {
            timer += 1
            if timer > nextJump {
                freq     = Double.random(in: 200...4000)
                nextJump = Int(sampleRate * Double.random(in: 0.01...0.04))
                timer    = 0
            }
            phase += 2.0 * Double.pi * freq / sampleRate
            let crackle: Float = Float.random(in: 0...1) > 0.7 ? Float.random(in: -0.3...0.3) : 0
            data[i] = (Float(sin(phase)) * 0.3 + crackle) * volume
        }
        scheduleAndPlay(buffer)
    }

    /// Linear frequency sweep with bell-curve amplitude envelope.
    func playSweep(
        from startFreq: Double = 120,
        to   endFreq:   Double = 2400,
        duration:       Double = 0.5,
        volume:         Float  = 0.4
    ) {
        guard let buffer = makeBuffer(frameCount: AVAudioFrameCount(sampleRate * duration)) else { return }
        let data   = buffer.floatChannelData![0]
        let frames = Int(buffer.frameLength)
        var phase  = 0.0
        for i in 0..<frames {
            let t        = Double(i) / Double(frames)
            let freq     = startFreq + (endFreq - startFreq) * t
            phase       += 2.0 * Double.pi * freq / sampleRate
            let envelope = Float(sin(Double.pi * t))
            data[i] = Float(sin(phase)) * envelope * volume
        }
        scheduleAndPlay(buffer)
    }

    // MARK: - Compound sounds

    /// Three-tone ascending chime played on receipt of a voice configuration.
    /// C5 → E5 → G5 (do-mi-sol) — a universally understood "success" motif.
    ///
    /// Deferred tones use `DSEBox` instead of `[weak self]` to avoid the Swift 6.2.3
    /// region-isolation error when `self` is task-isolated from a `@MainActor` caller.
    func playVoiceReceivedChime() {
        playBeep(frequency: 523.25, duration: 0.15, volume: 0.50)   // C5
        let box = DSEBox(self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            box.value?.playBeep(frequency: 659.25, duration: 0.15, volume: 0.55)  // E5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            box.value?.playBeep(frequency: 783.99, duration: 0.25, volume: 0.60)  // G5
        }
    }

    // MARK: - Ambient chatter loop

    /// Starts a randomised, looping stream of beeps / static / electricity / sweeps.
    /// Loops until `stopAmbientChatter()` is called.
    /// Uses a cancellable `Task` rather than recursive `DispatchQueue.main.asyncAfter`
    /// so the loop cannot pile up if `stopAmbientChatter()` is called late.
    func startAmbientChatter() {
        stopAmbientChatter()   // cancel any existing loop before starting a new one
        isChatterRunning = true
        let box = DSEBox(self)
        chatterTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let engine = box.value, engine.isChatterRunning else { return }
                let delay = Double.random(in: 0.06...0.40)
                switch Int.random(in: 0...3) {
                case 0:
                    engine.playBeep(
                        frequency: Double.random(in: 250...2200),
                        duration:  Double.random(in: 0.04...0.18),
                        volume:    Float.random(in: 0.18...0.45)
                    )
                case 1:
                    engine.playStatic(duration: Double.random(in: 0.03...0.10))
                case 2:
                    engine.playElectricity(duration: Double.random(in: 0.10...0.35))
                case 3:
                    engine.playSweep(
                        from:     Double.random(in: 80...500),
                        to:       Double.random(in: 600...3000),
                        duration: Double.random(in: 0.15...0.45)
                    )
                default:
                    break
                }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Stops the ambient chatter loop. The current sound finishes naturally.
    func stopAmbientChatter() {
        isChatterRunning = false
        chatterTask?.cancel()
        chatterTask = nil
    }

    // MARK: - Full stop

    func stop() {
        stopAmbientChatter()
        playerNode.stop()
        engine.stop()
    }

    // MARK: - Private: PCM helpers

    private func makeBuffer(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard frameCount > 0,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: sampleRate,
                  channels: 1
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        return buffer
    }

    private func scheduleAndPlay(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}

// MARK: - DSEBox

/// Non-actor-isolated weak reference box for `DigitalSoundEngine`.
///
/// Analogous to `WeakRef<T>` in `VoiceSystem.swift`.  Capturing `DSEBox` in
/// `DispatchQueue.main.asyncAfter` closures avoids the Swift 6.2.3 region-isolation
/// error "sending 'self' risks causing data races" that occurs when a task-isolated
/// `self` is captured by a `@MainActor`-inferred closure.
private final class DSEBox: @unchecked Sendable {
    weak var value: DigitalSoundEngine?
    init(_ engine: DigitalSoundEngine) { self.value = engine }
}

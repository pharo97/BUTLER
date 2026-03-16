import AVFoundation
import AudioToolbox
import Speech
import Observation

// MARK: - VAD constants (file-level to avoid @MainActor isolation)

/// RMS energy below this threshold counts as silence.
private let kVADSilenceThreshold: Float = 0.015
/// Number of consecutive silent buffers before auto-stop.
/// ~23ms per 1024-sample buffer @ 44.1 kHz → 35 buffers ≈ 800 ms.
private let kVADSilenceFrames: Int = 35

/// Barge-in: RMS must exceed this threshold (same as voice-activity threshold).
private let kBargeInThreshold: Float = 0.020
/// Barge-in: number of consecutive loud buffers (~70 ms) before cutting TTS.
/// Short enough to feel instant; long enough to reject plosives and background noise.
private let kBargeInFrames: Int = 3

/// Semantic VAD: minimum silent buffers (~300 ms) before an early endpoint fires.
/// Only applies when the transcript already ends with sentence-final punctuation.
/// Cuts ~500 ms off the perceived latency for complete questions/commands.
private let kVADEarlyEndpointFrames: Int = 13

/// Absolute listen timeout: fire `stopListening()` after this many buffers regardless
/// of whether the user spoke. At 44.1 kHz / 1024 samples ≈ 23 ms per buffer.
/// 350 buffers ≈ 8 seconds. Prevents `listen()` from hanging forever when:
///   • microphone permission is denied (audio tap receives only silent buffers)
///   • the user never speaks during the Q&A questioning phase
///   • any other condition that leaves `vad.hasSpoken` permanently false
private let kVADAbsoluteTimeoutFrames: Int = 350  // ~8 s

/// Returns `true` if `text` looks like a complete utterance (ends with `.`, `!`, or `?`).
private func isSentenceComplete(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count > 5 else { return false }
    return t.hasSuffix(".") || t.hasSuffix("!") || t.hasSuffix("?")
}

// MARK: - VADState

/// Mutable VAD counters accessed from the audio tap callback (background thread).
///
/// Extracted from VoiceSystem so the tap closure can read/write without crossing
/// the @MainActor boundary. The benign data race on Int/Bool is intentional —
/// a few stale reads won't affect VAD correctness.
private final class VADState: @unchecked Sendable {
    var silentCount:      Int    = 0
    var hasSpoken:        Bool   = false
    var latestTranscript: String = ""
    /// Total buffers received since last reset. Used for the absolute timeout
    /// (`kVADAbsoluteTimeoutFrames`) that fires `stopListening()` even if the
    /// user never speaks — prevents `listen()` from hanging forever when
    /// microphone permission is denied or the user stays silent.
    var totalFrameCount:  Int    = 0
    func reset() { silentCount = 0; hasSpoken = false; latestTranscript = ""; totalFrameCount = 0 }
}

/// Holds a weak reference without inheriting actor isolation.
///
/// In Swift 6.2.3 on macOS 26, capturing `[weak self]` where `self` is
/// `@MainActor @Observable` causes the closure to be inferred as `@MainActor`.
/// At runtime Swift injects `dispatch_assert_queue(main_q)` at the start of
/// the closure — crashing instantly when CoreAudio (or any other framework)
/// calls it from a background thread.
///
/// Capturing a `WeakRef<T>` does NOT trigger that inference because `WeakRef`
/// is not actor-isolated, making it safe inside audio tap callbacks, speech
/// recognition handlers, and any other background-thread closure.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - BargeInMonitor

/// Lightweight one-shot microphone monitor used exclusively during TTS playback.
///
/// ## Why a separate AVAudioEngine
///
/// The STT engine (`audioEngine` inside `VoiceSystem`) is stopped at the end of
/// every `listen()` call via `cleanupAudio()`. Rather than keeping it alive during
/// TTS synthesis (which tangles the recognition-request lifecycle), `BargeInMonitor`
/// starts its own minimal engine with a single input tap — then tears it down
/// as soon as the TTS turn ends or barge-in fires.
///
/// On macOS the CoreAudio HAL delivers the same hardware input stream to multiple
/// software clients simultaneously. Because the two engines run **sequentially**
/// (STT engine stops before barge-in engine starts), there is zero resource conflict.
///
/// ## Semantics
///
/// - `start(onDetected:)` arms the monitor. `onDetected` fires **exactly once**
///   after `kBargeInFrames` consecutive loud buffers and then goes quiet.
/// - `stop()` tears down the engine; safe to call redundantly or when never started.
/// - `@unchecked Sendable` — the benign data races on `frameCount`/`hasFired`
///   mirror the `VADState` pattern and are harmless for energy detection.
private final class BargeInMonitor: @unchecked Sendable {

    private let engine     = AVAudioEngine()
    private var isRunning  = false
    private var frameCount = 0
    private var hasFired   = false

    /// Arms the monitor. `onDetected` is invoked on the CoreAudio render thread
    /// and must not touch any actor-isolated state — wrap the call site in
    /// `Task { @MainActor in }`.
    func start(onDetected: @escaping @Sendable () -> Void) {
        guard !isRunning else { return }
        hasFired   = false
        frameCount = 0

        let inputNode = engine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] buffer, _ in
            guard !self.hasFired else { return }
            let rms = rmsForBuffer(buffer)
            if rms > kBargeInThreshold {
                self.frameCount += 1
                if self.frameCount >= kBargeInFrames {
                    self.hasFired = true
                    onDetected()
                }
            } else {
                self.frameCount = 0
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            inputNode.removeTap(onBus: 0)
            print("[BargeInMonitor] Failed to start: \(error)")
        }
    }

    /// Stops the engine and resets all state. Safe to call even if not running.
    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning  = false
        hasFired   = false
        frameCount = 0
    }
}

// MARK: - STTTapHandler

/// Owns the `SFSpeechAudioBufferRecognitionRequest` and all CoreAudio / Speech
/// callback closures from a **non-`@MainActor`** lexical scope.
///
/// ## Why this class exists
///
/// In Swift 6.2.3 on macOS 26, every closure defined inside a `@MainActor`
/// function is inferred as `@MainActor` — regardless of what it captures.
/// The compiler generates a thunk that calls `dispatch_assert_queue(main_q)`
/// before invoking the real closure body. CoreAudio delivers tap buffers on its
/// real-time render thread; that assertion fires on every buffer → crash.
///
/// Closures defined in methods of a **non-actor-isolated** class are NOT
/// inferred as `@MainActor`, so they are safe to call from any thread.
///
/// `@unchecked Sendable` rationale:
///   - `req.append(_:)` is documented for real-time audio thread use
///   - `vad` and `weakVS` are already `@unchecked Sendable`
private final class STTTapHandler: @unchecked Sendable {

    let req: SFSpeechAudioBufferRecognitionRequest
    let vad: VADState
    let weakVS: WeakRef<VoiceSystem>

    init(vad: VADState, weakVS: WeakRef<VoiceSystem>) {
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        self.req   = r
        self.vad   = vad
        self.weakVS = weakVS
    }

    /// Installs the CoreAudio tap. Call before `audioEngine.start()`.
    ///
    /// The tap block is defined here (inside a `nonisolated` method on a
    /// non-`@MainActor` class) so Swift 6.2.3 does NOT infer it as `@MainActor`.
    func installTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] buffer, _ in
            self.req.append(buffer)

            // Absolute timeout — fire stopListening() after ~8 s regardless of whether
            // the user spoke. Guards against mic-permission-denied (silent buffers only)
            // and users who stay silent during the Q&A phase.
            self.vad.totalFrameCount += 1
            if self.vad.totalFrameCount >= kVADAbsoluteTimeoutFrames {
                self.vad.totalFrameCount = 0   // reset so we don't fire on every subsequent buffer
                Task { @MainActor in self.weakVS.value?.stopListening() }
                return
            }

            let rms = rmsForBuffer(buffer)
            if rms > kVADSilenceThreshold {
                self.vad.hasSpoken   = true
                self.vad.silentCount = 0
            } else if self.vad.hasSpoken {
                self.vad.silentCount += 1
                // Early endpoint: sentence-final punctuation + 300 ms silence.
                // Fires ~500 ms sooner than the full 800 ms window for complete utterances.
                let earlyEndpoint = self.vad.silentCount >= kVADEarlyEndpointFrames
                    && isSentenceComplete(self.vad.latestTranscript)
                if earlyEndpoint || self.vad.silentCount >= kVADSilenceFrames {
                    self.vad.silentCount = 0
                    Task { @MainActor in self.weakVS.value?.stopListening() }
                }
            }
        }
    }

    /// Starts recognition and returns the task. The result callback is defined
    /// here (non-`@MainActor` lexical scope) for the same reason as `installTap`.
    func startRecognition(with recognizer: SFSpeechRecognizer) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: self.req) { [self] result, error in
            // Extract only Sendable values (String, Bool) from the non-Sendable
            // SFSpeechRecognitionResult BEFORE crossing into the @MainActor Task.
            // Sending the result object itself across isolation regions triggers
            // Swift 6.2.3 region-isolation error: "sending 'result' risks causing data races".
            let transcriptText = result?.bestTranscription.formattedString
            let isFinal        = result?.isFinal ?? false
            // Write partial transcript so the VAD tap can do early endpoint detection.
            if let text = transcriptText { self.vad.latestTranscript = text }
            Task { @MainActor in
                guard let vs = self.weakVS.value else { return }
                if let text = transcriptText {
                    vs.transcript = text
                    if isFinal { vs.finishListening(.success(text)) }
                } else if let error {
                    vs.finishListening(.failure(error))
                }
            }
        }
    }
}

// MARK: - VoiceSystem

/// Central façade for all speech I/O.
///
/// Owns the STT pipeline (SFSpeechRecognizer + AVAudioEngine) and
/// TTS pipeline (AVSpeechSynthesizer). Publishes real-time state so
/// GlassChamberView can reflect listening/speaking without direct coupling.
///
/// ## Two TTS paths
///
/// **Blocking** (`speak(_ text: String) async`):
///   Single-utterance path used by CompanionEngine for short proactive messages.
///   Awaits until synthesis is complete before returning.
///
/// **Streaming** (`queueSentence(_:)` + `drainQueue() async`):
///   Multi-sentence pipeline for user-initiated conversations. Each sentence is
///   queued to AVSpeechSynthesizer as soon as it arrives — so BUTLER starts
///   speaking while Claude is still generating the next sentence. Call `drainQueue()`
///   after the sentence loop ends to await the final utterance.
///
/// All methods and properties run on @MainActor. Callbacks from audio
/// and recognition sub-systems hop back via Task { @MainActor in … }.
@MainActor
@Observable
final class VoiceSystem {

    // MARK: - Observable state (drives UI)

    private(set) var isListening: Bool   = false
    private(set) var isSpeaking:  Bool   = false
    fileprivate(set) var transcript:  String = ""   // Live partial text while listening
    private(set) var amplitude:   Double = 0.0  // 0–1, drives pulse animation

    /// Set to `true` by HotkeyManager when ⌥Space is pressed.
    var activationRequested: Bool = false

    // MARK: - Voice profile + audio duck

    let voiceProfile: VoiceProfileManager

    /// Optional audio duck manager — set by AppDelegate after creation.
    var audioDuckManager: AudioDuckManager?

    /// Optional audio device manager — set by AppDelegate.
    /// Provides the CoreAudio DeviceID of the user-selected microphone.
    var audioDeviceManager: AudioDeviceManager?

    // MARK: - STT internals

    private let recognizer                          = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest:  SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:     SFSpeechRecognitionTask?
    private var listenContinuation:  UnsafeContinuation<String, Error>?

    // MARK: - VAD (Voice Activity Detection)

    /// Shared mutable state for the audio tap callback — lives outside
    /// @MainActor isolation so the background audio thread can touch it.
    private let vadState = VADState()

    // MARK: - Continuous conversation mode

    /// `true` while the always-on conversation loop is active.
    /// GlassChamberView observes this to switch the mic button to a stop indicator.
    private(set) var isContinuousMode: Bool = false

    /// Background task that owns the listen → handle → listen loop.
    private var continuousLoopTask: Task<Void, Never>?

    /// Barge-in hardware monitor — armed during TTS, nil at all other times.
    private var bargeInMonitor: BargeInMonitor?

    // MARK: - TTS internals

    private let synthesizer          = AVSpeechSynthesizer()
    // Blocking path (speak)
    private var blockingDelegate:    BlockingSynthDelegate?
    // Streaming path (queueSentence / drainQueue)
    private var streamingDelegate:   StreamingSynthDelegate?
    private var drainContinuation:   UnsafeContinuation<Void, Never>?
    // Amplitude simulation
    private var amplitudeTask:       Task<Void, Never>?

    // MARK: - TTS output engine (for non-default output device)

    /// When the user selects a specific output device, TTS audio is routed
    /// through a dedicated AVAudioEngine instead of the system default.
    /// `AVSpeechSynthesizer.write(_:toBufferCallback:)` generates PCM buffers
    /// which are scheduled on the player node → engine → selected device.
    private var ttsEngine:     AVAudioEngine?
    private var ttsPlayerNode: AVAudioPlayerNode?

    // MARK: - Init

    init(voiceProfile: VoiceProfileManager) {
        self.voiceProfile = voiceProfile
    }

    // MARK: - Permission check

    /// Requests speech recognition + microphone permissions.
    ///
    /// ## Why Task.detached
    ///
    /// `SFSpeechRecognizer.requestAuthorization` and `AVCaptureDevice.requestAccess`
    /// deliver their callbacks on a background XPC thread (TCC framework).
    ///
    /// In Swift 6.2.3 on macOS 26, closures created inside a `@MainActor` function
    /// are inferred as `@MainActor` — the compiler emits a thunk that calls
    /// `dispatch_assert_queue(main_q)` before invoking the real closure body.
    /// When TCC delivers the callback off-main, that assertion fires →
    /// `_dispatch_assert_queue_fail` crash (confirmed in Thread 11 crash report).
    ///
    /// `withUnsafeContinuation` only skips the *resumption* executor check; it does
    /// NOT prevent the *closure body* from being `@MainActor`-inferred.
    ///
    /// Fix: `Task.detached` moves the `requestAuthorization` call (and therefore
    /// the creation of the callback closure) outside the `@MainActor` context.
    /// The callback closure is then non-isolated and safe to call from any thread.
    func requestPermissions() async -> Bool {
        let speechGranted: Bool = await withUnsafeContinuation { cont in
            Task.detached {
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        }
        let micGranted: Bool = await withUnsafeContinuation { cont in
            Task.detached {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        return speechGranted && micGranted
    }

    // MARK: - CoreAudio prewarm

    /// Pre-warms the CoreAudio hardware graph on a background thread.
    ///
    /// Call once at app launch so the first `listen()` invocation is instant.
    /// CoreAudio's hardware initialisation can block for 1–3 seconds on the
    /// very first access; running it off the main thread prevents a beachball.
    func prewarmAudio() {
        Task.detached(priority: .background) {
            let prewarm = AVAudioEngine()
            _ = prewarm.inputNode   // triggers CoreAudio hardware-graph init
            prewarm.prepare()       // pre-allocates audio buffers
            // prewarm goes out of scope; the CoreAudio graph stays warm process-wide
        }
    }

    // MARK: - STT — listen()

    func listen() async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw ListenError.recognizerUnavailable
        }
        guard !isListening else { throw ListenError.alreadyListening }

        transcript  = ""
        isListening = true
        vadState.reset()

        // Recreate the audio engine on every listen() cycle.
        //
        // A stopped AVAudioEngine can retain stale CoreAudio graph state across
        // calls. On the second and later calls after stop(), inputNode.outputFormat
        // can return sampleRate = 0, which causes the audio tap to receive empty
        // buffers and the VAD to never fire — so listen() hangs indefinitely.
        // Allocating a fresh AVAudioEngine ensures a clean hardware graph every time.
        audioEngine = AVAudioEngine()

        // STTTapHandler owns the recognition request and all callback closures.
        // Its methods are nonisolated (non-@MainActor class), so closures defined
        // within them are NOT inferred as @MainActor — no dispatch_assert_queue crash.
        let tapHandler = STTTapHandler(vad: vadState, weakVS: WeakRef(self))
        recognitionRequest = tapHandler.req   // kept for cleanupAudio()

        // Apply the user's preferred microphone before starting the engine.
        // Must be done after accessing inputNode but before prepare()/start().
        // If the device ID can't be applied (e.g. device was unplugged),
        // CoreAudio silently falls back to the system default.
        let inputNode = audioEngine.inputNode
        applyInputDevice(to: inputNode)

        let format = inputNode.outputFormat(forBus: 0)
        tapHandler.installTap(on: inputNode, format: format)

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanupAudio()
            isListening = false
            throw ListenError.audioEngineFailed(error)
        }

        recognitionTask = tapHandler.startRecognition(with: recognizer)

        return try await withUnsafeThrowingContinuation { continuation in
            self.listenContinuation = continuation
        }
    }

    // MARK: - Input device routing

    /// Applies the user-selected microphone to the given input node.
    ///
    /// Uses the low-level CoreAudio `AudioUnitSetProperty` API because the
    /// Swift overlay exposes `AUAudioUnit.deviceID` as read-only on macOS.
    /// Device routing must be applied BEFORE `audioEngine.prepare()`.
    private func applyInputDevice(to inputNode: AVAudioInputNode) {
        guard let deviceID = audioDeviceManager?.selectedInputDeviceID,
              deviceID != 0,
              let au = inputNode.audioUnit else { return }

        // The input node's underlying AUHAL accepts kAudioOutputUnitProperty_CurrentDevice
        // to switch which physical microphone it reads from.
        var devID = deviceID
        AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    func stopListening() {
        guard isListening else { return }
        // Use vadState.latestTranscript as the authoritative source.
        //
        // self.transcript is updated inside Task { @MainActor in } dispatched from
        // startRecognition's callback. The VAD tap ALSO dispatches stopListening()
        // via Task { @MainActor in }. Both land on @MainActor as separate runloop items
        // — whichever queued first wins. When the VAD task runs before the transcript
        // update task, self.transcript is still "" → listen() returns "" → the handler
        // guard silently skips the turn, producing "nothing happened" for the user.
        //
        // vadState.latestTranscript is assigned SYNCHRONOUSLY in startRecognition's
        // callback (before crossing into the @MainActor Task), so it's always at
        // least as fresh as self.transcript and is never empty when the user spoke.
        let best = vadState.latestTranscript.isEmpty ? transcript : vadState.latestTranscript
        finishListening(.success(best))
    }

    fileprivate func finishListening(_ result: Result<String, Error>) {
        recognitionTask?.cancel()
        recognitionTask = nil
        cleanupAudio()
        isListening = false

        switch result {
        case .success(let text):  listenContinuation?.resume(returning: text)
        case .failure(let error): listenContinuation?.resume(throwing: error)
        }
        listenContinuation = nil
    }

    private func cleanupAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    // MARK: - Continuous conversation mode

    /// Starts an always-on listen → respond → listen loop.
    ///
    /// ## Flow per turn
    ///
    /// 1. `listen()` — mic on, VAD auto-endpoints after ~800 ms of silence.
    /// 2. `handler(transcript)` — caller runs the AI pipeline and queues TTS.
    /// 3. While TTS plays, `BargeInMonitor` watches for sustained voice (~70 ms).
    ///    If detected, `stopSpeaking()` is called immediately, `drainQueue()`
    ///    unblocks inside the handler, and the handler returns.
    /// 4. Loop restarts at step 1.
    ///
    /// The loop runs on `@MainActor` and exits when `stopContinuousConversation()`
    /// cancels the underlying task.
    ///
    /// - Parameter handler: Called on `@MainActor` with each completed transcript.
    ///   Must handle its own errors internally; the loop restarts `listen()`
    ///   regardless of whether the handler succeeds or fails.
    func startContinuousConversation(handler: @escaping @MainActor (String) async -> Void) {
        stopContinuousConversation()   // cancel any previous loop
        isContinuousMode = true

        let weakSelf = WeakRef(self)

        continuousLoopTask = Task { @MainActor in
            while let vs = weakSelf.value,
                  !Task.isCancelled,
                  vs.isContinuousMode {
                do {
                    // Phase 1: Listen — VAD auto-stops on 800 ms silence
                    let text    = try await vs.listen()
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !Task.isCancelled else { continue }

                    // Phase 2: Arm barge-in
                    //
                    // Spawns a child task that polls until isSpeaking becomes true
                    // (happens ~150-300 ms after the handler starts its first queueSentence),
                    // then starts the BargeInMonitor hardware tap.
                    //
                    // If the user speaks for ≥ 70 ms while TTS is active, the monitor
                    // calls stopSpeaking() on @MainActor, which resumes drainContinuation,
                    // which unblocks drainQueue(), which causes the handler to return.
                    let bargeTask = Task { @MainActor in
                        guard let vs = weakSelf.value else { return }
                        while !vs.isSpeaking, !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(30))
                        }
                        guard !Task.isCancelled, let vs = weakSelf.value, vs.isSpeaking else { return }

                        let monitor = BargeInMonitor()
                        vs.bargeInMonitor = monitor
                        monitor.start { [weakSelf] in
                            // Called on CoreAudio thread — hop to @MainActor
                            Task { @MainActor in
                                guard let vs = weakSelf.value, vs.isSpeaking else { return }
                                vs.stopSpeaking()
                            }
                        }
                    }

                    // Phase 3: Run AI + TTS — barge-in may cut it short
                    await handler(trimmed)

                    // Phase 4: TTS ended (or barged-in) — tear down barge-in
                    bargeTask.cancel()
                    vs.bargeInMonitor?.stop()
                    vs.bargeInMonitor = nil

                } catch {
                    // listen() failed (engine error, recognition unavailable, etc.)
                    // Surface the error to GlassChamberView's red banner via notification,
                    // then pause briefly before retrying to avoid thrashing on hard errors.
                    if !Task.isCancelled, weakSelf.value?.isContinuousMode == true {
                        let msg = error.localizedDescription
                        print("[VoiceSystem] Continuous listen error: \(msg)")
                        NotificationCenter.default.post(
                            name: Notification.Name("butlerConversationError"),
                            object: msg
                        )
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            weakSelf.value?.isContinuousMode = false
        }
    }

    /// Stops the continuous conversation loop and tears down barge-in monitoring.
    /// Any in-progress `listen()` call is cancelled; any in-progress TTS continues
    /// to its natural end unless the caller also calls `stopSpeaking()`.
    func stopContinuousConversation() {
        continuousLoopTask?.cancel()
        continuousLoopTask = nil
        bargeInMonitor?.stop()
        bargeInMonitor    = nil
        isContinuousMode  = false
    }

    // MARK: - TTS — Blocking path (single utterance)

    /// Synthesises `text` and awaits completion. Used by CompanionEngine for
    /// short proactive messages where the full text is available up front.
    func speak(_ text: String) async {
        guard !text.isEmpty else { return }
        let outputID = audioDeviceManager?.selectedOutputDeviceID ?? 0

        audioDuckManager?.duck()
        isSpeaking = true
        startAmplitudeSimulation()

        if outputID != 0 {
            // Route TTS through AVAudioEngine → selected output device
            await speakViaEngine(text, deviceID: outputID)
        } else {
            // Default path — AVSpeechSynthesizer plays to system output
            let utterance = makeUtterance(text)
            let delegate  = BlockingSynthDelegate { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isSpeaking = false
                    self?.stopAmplitudeSimulation()
                }
            }
            blockingDelegate      = delegate
            synthesizer.delegate  = delegate
            synthesizer.speak(utterance)

            while isSpeaking {
                try? await Task.sleep(for: .milliseconds(33))
            }
            blockingDelegate = nil
        }

        audioDuckManager?.restore()
    }

    // MARK: - TTS — Streaming path (sentence queue)

    /// Queues a single sentence for TTS playback and returns immediately.
    ///
    /// Call this for each sentence that arrives from `AIIntegrationLayer.sendStreaming()`.
    /// AVSpeechSynthesizer automatically plays queued utterances back-to-back.
    /// After the sentence loop, call `drainQueue()` to await the final utterance.
    func queueSentence(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let outputID = audioDeviceManager?.selectedOutputDeviceID ?? 0

        if outputID != 0 {
            queueSentenceViaEngine(cleaned, deviceID: outputID)
        } else {
            queueSentenceDirect(cleaned)
        }
    }

    /// Default streaming path — speaks directly through AVSpeechSynthesizer.
    private func queueSentenceDirect(_ cleaned: String) {
        // First sentence of this streaming batch — set up state + delegate
        if streamingDelegate == nil {
            audioDuckManager?.duck()
            let del = StreamingSynthDelegate()
            del.onQueueEmpty = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isSpeaking         = false
                    self.stopAmplitudeSimulation()
                    self.streamingDelegate  = nil
                    self.audioDuckManager?.restore()
                    self.drainContinuation?.resume()
                    self.drainContinuation = nil
                }
            }
            streamingDelegate    = del
            synthesizer.delegate = del
            isSpeaking           = true
            startAmplitudeSimulation()
        }

        streamingDelegate?.increment()
        synthesizer.speak(makeUtterance(cleaned))
    }

    /// Awaits until all sentences queued via `queueSentence()` have finished playing.
    /// Returns immediately if the queue is already empty.
    func drainQueue() async {
        // Already done — return immediately
        guard isSpeaking else { return }

        await withUnsafeContinuation { [self] (continuation: UnsafeContinuation<Void, Never>) in
            // Double-check under actor lock (no race — everything is @MainActor)
            if !self.isSpeaking {
                continuation.resume()
            } else {
                self.drainContinuation = continuation
            }
        }
    }

    // MARK: - TTS — Engine-routed paths (non-default output device)

    /// Blocking speak routed through AVAudioEngine to a specific output device.
    private func speakViaEngine(_ text: String, deviceID: AudioDeviceID) async {
        prepareTTSEngine(deviceID: deviceID)

        guard let player = ttsPlayerNode, let engine = ttsEngine else {
            isSpeaking = false
            stopAmplitudeSimulation()
            return
        }

        let utterance = makeUtterance(text)

        // write() generates PCM buffers on a background thread; schedule them
        // on the player node as they arrive.
        // WeakRef prevents [weak self] from causing @MainActor inference on this
        // callback — AVSpeechSynthesizer.write delivers buffers on a background thread.
        let weakSelf = WeakRef(self)
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                // Empty buffer = synthesis complete
                Task { @MainActor in
                    // Wait for the player to finish playing all scheduled buffers
                    guard let vs = weakSelf.value, let p = vs.ttsPlayerNode else { return }
                    // Schedule a completion handler on the last buffer
                    p.scheduleBuffer(AVAudioPCMBuffer(
                        pcmFormat: engine.outputNode.outputFormat(forBus: 0),
                        frameCapacity: 0
                    )!) {
                        Task { @MainActor in
                            weakSelf.value?.isSpeaking = false
                            weakSelf.value?.stopAmplitudeSimulation()
                            weakSelf.value?.stopTTSEngine()
                        }
                    }
                }
                return
            }
            player.scheduleBuffer(pcm)
        }
    }

    /// Streaming queue routed through AVAudioEngine to a specific output device.
    private func queueSentenceViaEngine(_ cleaned: String, deviceID: AudioDeviceID) {
        // First sentence — prepare engine + state
        if ttsEngine == nil {
            prepareTTSEngine(deviceID: deviceID)
            audioDuckManager?.duck()
            isSpeaking = true
            startAmplitudeSimulation()
        }

        guard let player = ttsPlayerNode else { return }

        let utterance = makeUtterance(cleaned)
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                return  // synthesis of this sentence complete
            }
            player.scheduleBuffer(pcm)
        }
    }

    // MARK: - TTS engine lifecycle

    /// Creates and starts an AVAudioEngine routed to the given output device.
    private func prepareTTSEngine(deviceID: AudioDeviceID) {
        guard ttsEngine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        // Connect player → mainMixer → output
        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Route to the selected output device
        if let au = engine.outputNode.audioUnit {
            var devID = deviceID
            AudioUnitSetProperty(
                au,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        engine.prepare()
        do {
            try engine.start()
            player.play()
            ttsEngine     = engine
            ttsPlayerNode = player
        } catch {
            print("[VoiceSystem] TTS engine failed to start: \(error)")
        }
    }

    /// Tears down the TTS output engine.
    private func stopTTSEngine() {
        ttsPlayerNode?.stop()
        ttsEngine?.stop()
        if let player = ttsPlayerNode {
            ttsEngine?.detach(player)
        }
        ttsEngine     = nil
        ttsPlayerNode = nil
    }

    // MARK: - Stop

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        stopTTSEngine()
        isSpeaking = false
        stopAmplitudeSimulation()
        audioDuckManager?.restore()
        // Clean up both paths
        blockingDelegate   = nil
        streamingDelegate  = nil
        // Unblock drainQueue() if it was waiting
        drainContinuation?.resume()
        drainContinuation = nil
    }

    // MARK: - Utterance factory

    /// Creates an utterance applying the user's selected voice.
    ///
    /// Voice resolution order:
    ///   1. `butler.tts.voiceIdentifier` (canonical key, written by `VoiceSelectionView`
    ///      during onboarding and by the Settings voice-change sheet).
    ///   2. `VoiceProfileManager.selectedVoice` (persisted across launches under
    ///      `butler.selectedVoiceIdentifier.v1`).
    ///   3. System default English voice.
    ///
    /// Using the canonical key first ensures the onboarding-chosen voice is applied
    /// immediately on the same launch, before `VoiceProfileManager` re-reads its
    /// UserDefaults on the next app start.
    func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)

        if let id    = UserDefaults.standard.string(forKey: "butler.tts.voiceIdentifier"),
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            u.voice = voice
        } else if let profileVoice = voiceProfile.selectedVoice {
            u.voice = profileVoice
        } else {
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        u.rate            = voiceProfile.speakingRate
        u.pitchMultiplier = 1.0
        u.volume          = 0.9
        return u
    }

    // MARK: - Amplitude simulation

    private func startAmplitudeSimulation() {
        var phase = 0.0
        amplitudeTask = Task { @MainActor [weak self] in
            while let self, self.isSpeaking, !Task.isCancelled {
                phase += 0.18
                let amp = 0.35
                    + 0.40 * sin(phase)
                    + 0.15 * sin(phase * 2.3)
                    + 0.10 * sin(phase * 5.1)
                self.amplitude = max(0, min(1, amp))
                try? await Task.sleep(for: .milliseconds(33))
            }
            self?.amplitude = 0.0
        }
    }

    private func stopAmplitudeSimulation() {
        amplitudeTask?.cancel()
        amplitudeTask = nil
        amplitude = 0.0
    }

    // MARK: - VAD helper

    // rmsForBuffer moved to file scope — see bottom of file.

    // MARK: - Errors

    enum ListenError: Error, LocalizedError {
        case recognizerUnavailable
        case alreadyListening
        case audioEngineFailed(Error)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:    return "Speech recognition is not available."
            case .alreadyListening:         return "Already listening."
            case .audioEngineFailed(let e): return "Audio engine failed: \(e.localizedDescription)"
            }
        }
    }
}

// MARK: - VAD helper (file-scope)

/// Computes the RMS (root-mean-square) energy of an audio buffer.
///
/// Defined at **file scope** (not inside `VoiceSystem`) so it carries no
/// `@MainActor` association. Calling a `static func` on a `@MainActor` class
/// from a `@unchecked Sendable` context triggers Swift 6.2.3 region-isolation
/// error "sending 'buffer' risks causing data races" because the compiler
/// infers the call crosses an actor-region boundary.
///
/// As a plain free function, no actor boundary is crossed and the buffer is
/// consumed without region transfer.
private func rmsForBuffer(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData?[0],
          buffer.frameLength > 0 else { return 0 }
    let frameCount = Int(buffer.frameLength)
    var sum: Float = 0
    for i in 0..<frameCount {
        let s = channelData[i]
        sum += s * s
    }
    return sqrt(sum / Float(frameCount))
}

// MARK: - BlockingSynthDelegate
// Used by speak() — fires when the single utterance finishes.

private final class BlockingSynthDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}

// MARK: - StreamingSynthDelegate
// Used by queueSentence() — tracks pending count, fires when ALL utterances finish.

private final class StreamingSynthDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onQueueEmpty: (() -> Void)?
    private var pendingCount: Int = 0

    /// Call once per `synthesizer.speak(utterance)` call, BEFORE speaking.
    func increment() { pendingCount += 1 }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pendingCount = max(0, pendingCount - 1)
        if pendingCount == 0 { onQueueEmpty?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        pendingCount = 0
        onQueueEmpty?()
    }
}

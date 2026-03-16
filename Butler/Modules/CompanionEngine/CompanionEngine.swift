import Foundation

// MARK: - CompanionEngine

/// The proactive brain of BUTLER.
///
/// Runs a background loop that continuously evaluates whether BUTLER should
/// speak up without being asked. When the `InterventionEngine` gives the
/// green light — or a high-priority trigger fires (clipboard change, imminent
/// calendar event) — `CompanionEngine` generates a context-aware suggestion,
/// streams it, and speaks it through `VoiceSystem`.
///
/// This is what makes BUTLER a companion, not just a voice widget.
///
/// ## Latency optimisations (Phase 2)
///
/// **Context cache** — `PerceptionLayer.gatherContext(captureScreen: false)` results
/// are cached for 2 seconds inside `PerceptionLayer`, eliminating redundant
/// AppleScript / pasteboard reads on back-to-back poll cycles.
///
/// **Model routing** — Proactive interventions use the cheapest model that's
/// still appropriate for the detected context. Haiku (~3× faster) handles quick
/// browsing and comms nudges; Sonnet handles deeper coding / writing sessions.
///
/// **Clipboard pre-warm** — When the user copies text with Tier 1 enabled,
/// BUTLER immediately fires a background `sendSilent` call. If the standard
/// evaluation loop fires a clipboard-triggered intervention within 60 seconds,
/// the pre-warmed response is used directly — zero additional API latency.
///
/// Loop behaviour:
///   • Polls every `pollInterval` seconds (default 30s)
///   • Initial delay of 90s — don't interrupt the user immediately on launch
///   • Skips if BUTLER is already listening or speaking
///   • Skips if API key is not configured
///   • Skips if context is unknown or a kill-switch is active
///   • Clipboard changes and imminent meetings bypass the score threshold
///   • All hard rate-limiting is handled by `InterventionEngine`
@MainActor
@Observable
final class CompanionEngine {

    // MARK: - Tuning

    static let pollInterval:    Duration = .seconds(30)
    static let launchDelay:     Duration = .seconds(90)
    /// How long in writing context before BUTLER offers writing assistance (10 min).
    private static let writingAssistanceThreshold: TimeInterval = 600
    /// How long a pre-warmed clipboard response stays valid.
    private static let prewarmTTL: TimeInterval = 60

    // MARK: - State

    private(set) var isActive:             Bool   = false
    private(set) var lastFiredAt:          Date?  = nil
    private(set) var lastSuggestion:       String = ""
    /// `true` while BUTLER is speaking a proactive suggestion.
    /// GlassChamberView observes this to show the dismiss button.
    private(set) var isProactiveSpeaking:  Bool   = false

    // MARK: - Dependencies

    private let activityMonitor:    ActivityMonitor
    private let permissionSecurity: PermissionSecurityManager
    private let interventionEngine: InterventionEngine
    private let aiLayer:            AIIntegrationLayer
    private let voiceSystem:        VoiceSystem
    private let visualEngine:       VisualizationEngine
    private let perception:         PerceptionLayer
    private let tierManager:        PermissionTierManager
    private let rhythmTracker:      DailyRhythmTracker

    // MARK: - Private — loop tasks

    private var loopTask:          Task<Void, Never>?
    private var clipboardWatchTask: Task<Void, Never>?

    // MARK: - Private — dedup state

    private var lastClipboardTimestamp: Date?   // de-duplicate clipboard triggers
    private var lastMeetingAlert: String = ""   // de-duplicate meeting alerts
    /// Tracks continuous time in .writing context for writing-assistance behavior.
    private var writingContextStartedAt: Date? = nil

    // MARK: - Private — clipboard pre-warm cache

    /// A speculatively-generated Claude response cached when the clipboard changes.
    private struct PrewarmEntry {
        let clipboardText: String   // the clipboard content this was generated for
        let response:      String   // the pre-warmed suggestion
        let generatedAt:   Date
    }

    private var prewarmCache: PrewarmEntry?
    /// Timestamp of the last clipboard change for which we started a pre-warm.
    private var lastPrewarmedClipboardTimestamp: Date?
    /// `true` while a background pre-warm call is in-flight (prevents duplicate calls).
    private var isPrewarming: Bool = false

    // MARK: - Init

    init(
        activityMonitor:    ActivityMonitor,
        permissionSecurity: PermissionSecurityManager,
        interventionEngine: InterventionEngine,
        aiLayer:            AIIntegrationLayer,
        voiceSystem:        VoiceSystem,
        visualEngine:       VisualizationEngine,
        perception:         PerceptionLayer,
        tierManager:        PermissionTierManager,
        rhythmTracker:      DailyRhythmTracker
    ) {
        self.activityMonitor    = activityMonitor
        self.permissionSecurity = permissionSecurity
        self.interventionEngine = interventionEngine
        self.aiLayer            = aiLayer
        self.voiceSystem        = voiceSystem
        self.visualEngine       = visualEngine
        self.perception         = perception
        self.tierManager        = tierManager
        self.rhythmTracker      = rhythmTracker
    }

    // MARK: - Lifecycle

    func start() {
        isActive = true

        // Main proactive evaluation loop (30s cadence, 90s initial delay)
        loopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            while !Task.isCancelled {
                await self?.evaluate()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }

        // Clipboard pre-warm watcher (2s cadence — matches ClipboardMonitor.pollInterval)
        clipboardWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.triggerPrewarmIfNeeded()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        clipboardWatchTask?.cancel()
        isActive = false
    }

    // MARK: - Evaluation

    /// Called every `pollInterval`. Decides whether and why to fire an intervention.
    private func evaluate() async {
        let context = activityMonitor.context
        let appName = activityMonitor.frontmostAppName

        // Pre-flight checks — bail fast before hitting the AI
        guard
            !voiceSystem.isListening,               // don't interrupt the user talking
            !voiceSystem.isSpeaking,                // don't talk over ourselves
            !aiLayer.isStreaming,                   // not mid-response
            !aiLayer.apiKey.isEmpty                 // key must be configured
        else { return }

        // Tier 2 gate — proactive interventions require explicit user opt-in
        guard tierManager.tier2Enabled else { return }

        // Track writing context duration for writing-assistance behavior
        updateWritingTimer(context: context)

        // Gather perception snapshot — context cache in PerceptionLayer handles the 2s TTL
        let screenCtx = await perception.gatherContext(
            activity: activityMonitor,
            captureScreen: false    // proactive polls never use full OCR (too slow)
        )

        // --- High-priority triggers (bypass score threshold) ---
        // Tier 1 gate: clipboard + calendar context require screen/clipboard access
        if tierManager.tier1Enabled {

            // 1. Clipboard: new text pasted that we haven't reacted to yet
            if let clip = perception.clipboardMonitor.latestChange,
               clip.timestamp != lastClipboardTimestamp,
               !interventionEngine.isHardRateLimited() {
                lastClipboardTimestamp = clip.timestamp
                let hint = clipboardHint(text: clip.text, appName: appName)
                // Use pre-warm cache if available for this clipboard content
                let prewarmed = consumePrewarm(for: clip.text)
                await fireIntervention(context: context, appName: appName,
                                       screenContext: screenCtx, triggerHint: hint,
                                       prewarmedResponse: prewarmed)
                return
            }

            // 2. Imminent calendar event (within 5 min) that we haven't warned about
            let meetingSummary = perception.calendarBridge.nextEventSummary(withinMinutes: 5)
            if !meetingSummary.isEmpty,
               meetingSummary != lastMeetingAlert,
               !interventionEngine.isHardRateLimited() {
                lastMeetingAlert = meetingSummary
                let hint = "The user has '\(meetingSummary)'. Give them a brief heads-up so they can wrap up."
                await fireIntervention(context: context, appName: appName,
                                       screenContext: screenCtx, triggerHint: hint)
                return
            }
        }

        // --- Companion Behavior: Writing Assistance ---
        // After 10+ uninterrupted minutes in a writing app, offer structural help.
        if let writingStart = writingContextStartedAt,
           context == .writing,
           Date().timeIntervalSince(writingStart) >= Self.writingAssistanceThreshold,
           !interventionEngine.isHardRateLimited() {
            writingContextStartedAt = nil  // reset so we don't repeat immediately
            let hint = "The user has been writing in \(appName) for a while. Offer a natural, brief suggestion about structure, clarity, or next steps — only if it feels genuinely helpful. Don't be pushy."
            await fireIntervention(context: .writing, appName: appName,
                                   screenContext: screenCtx, triggerHint: hint)
            return
        }

        // --- Standard scored intervention ---
        guard
            context != .unknown,
            interventionEngine.shouldIntervene(context: context)
        else { return }

        await fireIntervention(context: context, appName: appName, screenContext: screenCtx, triggerHint: nil)
    }

    /// Maintains a continuous timer for how long the user has been in the writing context.
    /// Resets when they switch away; cleared after writing assistance fires.
    private func updateWritingTimer(context: ButlerContext) {
        if context == .writing {
            if writingContextStartedAt == nil {
                writingContextStartedAt = Date()
            }
        } else {
            writingContextStartedAt = nil
        }
    }

    // MARK: - Fire

    private func fireIntervention(
        context: ButlerContext,
        appName: String,
        screenContext: ScreenContext,
        triggerHint: String?,
        prewarmedResponse: String? = nil
    ) async {
        interventionEngine.recordInterventionFired()
        lastFiredAt = Date()

        // Memory Palace: log that a proactive suggestion was shown for this context.
        let topicLabel = appName.isEmpty ? context.displayName : "\(context.displayName) in \(appName)"
        MemoryWriter.shared.appendFact(
            "Proactive suggestion shown: \(topicLabel)",
            to: .habits
        )

        do {
            let suggestion: String

            if let prewarmed = prewarmedResponse,
               !prewarmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // ⚡ Pre-warm cache hit — zero additional API latency
                suggestion = prewarmed
                // Append to context window so follow-up conversations have continuity
                aiLayer.appendAssistantResponse(suggestion)
                print("[CompanionEngine] ⚡ Pre-warm hit — skipping API call")
            } else {
                // Standard path — ask Claude
                visualEngine.setState(.thinking)
                suggestion = try await aiLayer.sendProactive(
                    context:      context,
                    appName:      appName,
                    screenContext: screenContext,
                    triggerHint:  triggerHint,
                    model:        modelID(for: context)
                )
            }

            guard !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                visualEngine.setState(.idle)
                return
            }

            lastSuggestion = suggestion

            // Speak it — flag tells GlassChamberView to show the dismiss button.
            // `defer` guarantees the flag clears even when the user interrupts.
            isProactiveSpeaking = true
            defer { isProactiveSpeaking = false }

            visualEngine.setState(.speaking)
            await voiceSystem.speak(suggestion)
            visualEngine.setState(.idle)

        } catch {
            visualEngine.setState(.idle)
            // Silently swallow — proactive failures should never surface to the user
            print("[CompanionEngine] Proactive intervention failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Model routing

    /// Returns the appropriate Claude model for a given context.
    ///
    /// Routing strategy:
    ///   - **Haiku** (~3× faster) for shallow contexts: browsing, comms, unknown.
    ///     These interventions are brief nudges that don't require deep reasoning.
    ///   - **Sonnet** for deep-work contexts: coding, writing, creative, productivity.
    ///     These benefit from stronger reasoning and are worth the extra 200–400ms.
    ///
    /// Falls back to `selectedModel` (user's choice) for non-Claude providers.
    private func modelID(for context: ButlerContext) -> String {
        guard aiLayer.selectedProvider == .claude else {
            return aiLayer.selectedModel
        }
        switch context {
        case .coding, .writing, .creative, .productivity:
            return "claude-sonnet-4-5"   // deeper reasoning for substantive work
        case .browsing, .comms, .unknown, .videoCall:
            return "claude-haiku-4-5"    // fast and cheap for quick nudges
        }
    }

    // MARK: - Clipboard pre-warm

    /// Checks for a new clipboard change and, if conditions are met, fires a speculative
    /// Claude call in the background so the response is ready before the evaluation
    /// loop's 30-second poll cycle catches the same clipboard event.
    private func triggerPrewarmIfNeeded() async {
        // Pre-flight: Tier 1 required; don't stack pre-warms; must have a key
        guard
            tierManager.tier1Enabled,
            !isPrewarming,
            !aiLayer.apiKey.isEmpty
        else { return }

        // Only trigger when there's a new clipboard change
        guard
            let clip = perception.clipboardMonitor.latestChange,
            clip.timestamp != lastPrewarmedClipboardTimestamp
        else { return }

        lastPrewarmedClipboardTimestamp = clip.timestamp
        isPrewarming = true

        // Capture all @MainActor values before spawning the fire-and-forget task
        let context   = activityMonitor.context
        let appName   = activityMonitor.frontmostAppName
        let system    = PromptBuilder.proactiveSystemPrompt(
            context:     context,
            appName:     appName,
            screenContext: nil,
            triggerHint: clipboardHint(text: clip.text, appName: appName)
        )
        let model     = modelID(for: context)
        let clipText  = clip.text

        // Fire-and-forget: the result is stored in `prewarmCache` without blocking
        // the clipboard watch loop or updating any streaming UI state.
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await self.aiLayer.sendSilent(system: system, model: model)
                self.prewarmCache = PrewarmEntry(
                    clipboardText: clipText,
                    response:      response,
                    generatedAt:   Date()
                )
                print("[CompanionEngine] ⚡ Pre-warm ready (\(clipText.count) chars copied)")
            } catch {
                print("[CompanionEngine] Pre-warm failed: \(error.localizedDescription)")
            }
            self.isPrewarming = false
        }
    }

    /// Returns and consumes the pre-warm cache if it matches `clipboardText`
    /// and was generated within `prewarmTTL` seconds.
    private func consumePrewarm(for clipboardText: String) -> String? {
        guard
            let cached = prewarmCache,
            cached.clipboardText == clipboardText,
            Date().timeIntervalSince(cached.generatedAt) < Self.prewarmTTL
        else { return nil }
        prewarmCache = nil  // consume: each pre-warm is used at most once
        return cached.response
    }

    // MARK: - Outcome recording

    /// Call when the user responds positively after a proactive suggestion.
    func recordAccepted() {
        interventionEngine.recordAccepted(context: activityMonitor.context)
        rhythmTracker.recordAccept()
    }

    /// Call when the user dismisses or ignores a proactive suggestion.
    func recordDismissed() {
        interventionEngine.recordDismissed(context: activityMonitor.context)
        rhythmTracker.recordDismiss()
    }

    /// Call when the user manually taps the mic (strongest positive engagement signal).
    func recordManualTrigger() {
        interventionEngine.recordManualTrigger(context: activityMonitor.context)
        rhythmTracker.recordManualTrigger()
    }

    // MARK: - Clipboard hint builder

    private func clipboardHint(text: String, appName: String) -> String {
        let preview = String(text.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        let app = appName.isEmpty ? "their current app" : appName
        return "The user just copied this text in \(app): \"\(preview)\". If it seems like something they might want help with (code, an error, a URL, a question), offer a brief, natural observation or ask if they need a hand — otherwise stay silent."
    }
}

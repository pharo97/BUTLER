import Foundation

// MARK: - PromptBuilder

/// Builds system prompts for BUTLER's AI backend.
///
/// Two modes:
///   • `systemPrompt(context:appName:)` — used for every user-initiated conversation.
///     Injects the detected context so BUTLER responds like it knows what you're doing.
///   • `proactiveSystemPrompt(context:appName:)` — used for CompanionEngine interventions.
///     Shorter, more pointed: BUTLER is speaking first without being asked.
///
/// Customisation injections (Feature 1 & 2):
///   • `butler.ai.customName`        — replaces "BUTLER" in the opening persona line.
///   • `butler.ai.personalityPrompt` — injects a user-defined personality directive.
///   • `MemoryWriter.shared`         — when enabled, prepends recent memory facts.
enum PromptBuilder {

    // MARK: - UserDefaults keys

    private static let nameKey:        String = "butler.ai.customName"
    private static let personalityKey: String = "butler.ai.personalityPrompt"

    // MARK: - Resolved values

    /// The display name used inside prompts. Defaults to "BUTLER".
    static var resolvedName: String {
        let stored = UserDefaults.standard.string(forKey: nameKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BUTLER" : trimmed
    }

    private static var resolvedPersonality: String {
        UserDefaults.standard.string(forKey: personalityKey) ?? ""
    }

    // MARK: - Standard system prompt

    /// Context-aware system prompt for user-initiated conversations.
    static func systemPrompt(
        context: ButlerContext = .unknown,
        appName: String = "",
        screenContext: ScreenContext? = nil
    ) -> String {
        let name = resolvedName
        let contextLine     = contextSentence(context: context, appName: appName)
        let screenCtxBlock  = screenContextBlock(screenContext: screenContext, appName: appName)

        // Build personality block — injected at the top before the fixed rules
        var personalityBlock = ""
        let personality = resolvedPersonality.trimmingCharacters(in: .whitespacesAndNewlines)
        if !personality.isEmpty {
            personalityBlock = "PERSONALITY DIRECTIVE: \(personality)\n\n"
        }

        // Memory Palace injection
        var memoryBlock = ""
        if MemoryWriter.shared.includeInPrompts {
            let facts = MemoryWriter.shared.allRecentFacts(limit: 30)
            if !facts.isEmpty {
                memoryBlock = "\n\n\(facts)"
            }
        }

        return """
        You are \(name), a concise AI operating companion living in a floating glass interface \
        on the user's macOS desktop. You respond through voice — your words are \
        immediately spoken aloud by text-to-speech.
        \(personalityBlock.isEmpty ? "" : "\n\(personalityBlock)")
        Personality (defaults — overridden by PERSONALITY DIRECTIVE above if present):
        - Direct, perceptive, and quietly confident. Never sycophantic.
        - Occasionally dry wit when appropriate, never forced.
        - You speak like an extremely competent colleague, not a chatbot.
        - You are aware of what the user is working on and adapt your tone accordingly.

        Voice response rules (CRITICAL — you output audio, not text):
        - Keep responses to 1–3 sentences unless the user explicitly asks for more detail.
        - No markdown, no bullet points, no headers, no asterisks.
        - No "Certainly!" / "Great question!" / "Of course!" openers. Ever.
        - Numbers: spell out if less than 10, use numerals if 10 or more.
        - Dates: say "March sixth" not "3/6" or "2026-03-06".
        - If you don't know something, say so in one short sentence.

        SYSTEM ACTIONS (use when the user asks you to open an app, open a URL, or adjust volume):
        Append action lines at the very END of your response, each on its own line.
        These lines are NEVER spoken aloud — only your natural text is.
        Format exactly:
          BUTLER_DO: open_app AppName
          BUTLER_DO: open_url https://example.com
          BUTLER_DO: set_volume 40
          BUTLER_DO: run_shortcut ShortcutName
        Example: "Sure, opening Safari now." followed by "BUTLER_DO: open_app Safari"

        Current context:
        \(contextLine)\
        - Today's date: \(formattedDate()). Current time: \(formattedTime()).
        - The user interacts via push-to-talk voice. Latency matters — be fast, be sharp.\
        \(screenCtxBlock.isEmpty ? "" : "\n\n" + screenCtxBlock)\
        \(memoryBlock)
        """
    }

    // MARK: - Proactive system prompt

    /// System prompt for CompanionEngine-initiated interventions.
    /// BUTLER is speaking first — must be brief, natural, non-intrusive.
    static func proactiveSystemPrompt(
        context: ButlerContext,
        appName: String,
        screenContext: ScreenContext? = nil,
        triggerHint: String? = nil
    ) -> String {
        let hint = triggerHint ?? proactiveHint(for: context, appName: appName)

        return """
        \(systemPrompt(context: context, appName: appName, screenContext: screenContext))

        PROACTIVE MODE — You are initiating this conversation without being asked.
        \(hint)

        Rules for this proactive message (non-negotiable):
        - Maximum 1 sentence. One. Not two.
        - Sound like a sharp colleague who noticed something — not an assistant seeking a task.
        - Never say "I noticed", "I see you're", "As your AI assistant", or anything robotic.
        - Ask one genuine question OR make one brief observation. Never both.
        - If nothing useful comes to mind, say something minimal like "How's it going?"
        """
    }

    // MARK: - Private helpers

    private static func contextSentence(context: ButlerContext, appName: String) -> String {
        guard context != .unknown else { return "" }
        let app = appName.isEmpty ? "" : " in \(appName)"
        return "- User is currently \(context.displayName.lowercased())\(app).\n"
    }

    /// Builds the CURRENT SCREEN CONTEXT block injected into the system prompt.
    ///
    /// This block tells Claude exactly what the user is looking at right now:
    /// their active app, browser URL, clipboard, selected text, upcoming calendar
    /// events, and optionally a screen OCR dump. This is what powers answers to
    /// "what am I working on?" and "what do you see?".
    ///
    /// Only included when there is at least one non-empty field to report —
    /// avoids adding noise to the prompt when no perception data is available.
    private static func screenContextBlock(screenContext: ScreenContext?, appName: String) -> String {
        guard let ctx = screenContext, !ctx.isEmpty else { return "" }

        var lines: [String] = ["CURRENT SCREEN CONTEXT (what the user is looking at right now):"]

        // Active app — always include if we have any context at all
        let activeApp = ctx.appName.isEmpty ? appName : ctx.appName
        if !activeApp.isEmpty {
            lines.append("  Active app: \(activeApp)")
        }

        if !ctx.browserURL.isEmpty {
            lines.append("  Browser URL: \(ctx.browserURL)")
        }
        if !ctx.selectedText.isEmpty {
            let truncated = String(ctx.selectedText.prefix(300))
            lines.append("  Selected text: \"\(truncated)\"")
        }
        if !ctx.clipboardText.isEmpty {
            let truncated = String(ctx.clipboardText.prefix(200))
            lines.append("  Clipboard: \"\(truncated)\"")
        }
        if !ctx.upcomingEventSummary.isEmpty {
            lines.append("  Upcoming event: \(ctx.upcomingEventSummary)")
        }
        if !ctx.screenOCRText.isEmpty {
            let truncated = String(ctx.screenOCRText.prefix(600))
            lines.append("  Screen content (OCR): \"\(truncated)\"")
        }

        lines.append("When asked \"what am I working on\" or \"what do you see\", answer from this context.")

        return lines.joined(separator: "\n")
    }

    private static func proactiveHint(for context: ButlerContext, appName: String) -> String {
        let app = appName.isEmpty ? "their editor" : appName
        switch context {
        case .coding:
            return "The user is coding in \(app). Check in on their work — offer to think through a problem or ask how it's going."
        case .writing:
            return "The user is writing in \(app). They might want a thought partner, help with phrasing, or just a quick check-in."
        case .browsing:
            return "The user is browsing. They may be researching something — a brief, non-presumptuous offer to help could land well."
        case .comms:
            return "The user is handling communications. A quick offer to help draft or summarise something might be useful."
        case .productivity:
            return "The user is doing productivity work. A useful nudge or brief observation could help them stay on track."
        case .creative:
            return "The user is doing creative work. Be extremely brief — don't interrupt flow, just check in lightly."
        case .videoCall, .unknown:
            return "Keep it extremely brief and neutral."
        }
    }

    private static func formattedDate() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: Date())
    }

    private static func formattedTime() -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: Date())
    }
}

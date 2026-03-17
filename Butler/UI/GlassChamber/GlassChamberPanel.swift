import AppKit
import SwiftUI

/// The floating Glass Chamber window.
///
/// Implemented as a non-activating NSPanel so BUTLER never steals focus
/// from the user's active application.
final class GlassChamberPanel: NSPanel {

    private let engine:              VisualizationEngine
    private let voiceSystem:         VoiceSystem
    private let aiLayer:             AIIntegrationLayer
    private let activityMonitor:     ActivityMonitor
    private let hotkeyManager:       HotkeyManager
    private let perception:          PerceptionLayer
    private let automationEngine:    AutomationEngine
    private let companionEngine:     CompanionEngine
    // Phase 2 additions
    private let tierManager:         PermissionTierManager
    private let learningSystem:      LearningSystem
    private let interventionEngine:  InterventionEngine
    private let rhythmTracker:       DailyRhythmTracker
    private let permissionSecurity:  PermissionSecurityManager
    private let audioDeviceManager:  AudioDeviceManager
    private let idleProcessor:       IdleBackgroundProcessor

    init(
        engine:              VisualizationEngine,
        voiceSystem:         VoiceSystem,
        aiLayer:             AIIntegrationLayer,
        activityMonitor:     ActivityMonitor,
        hotkeyManager:       HotkeyManager,
        perception:          PerceptionLayer,
        automationEngine:    AutomationEngine,
        companionEngine:     CompanionEngine,
        tierManager:         PermissionTierManager,
        learningSystem:      LearningSystem,
        interventionEngine:  InterventionEngine,
        rhythmTracker:       DailyRhythmTracker,
        permissionSecurity:  PermissionSecurityManager,
        audioDeviceManager:  AudioDeviceManager,
        idleProcessor:       IdleBackgroundProcessor
    ) {
        self.engine              = engine
        self.voiceSystem         = voiceSystem
        self.aiLayer             = aiLayer
        self.activityMonitor     = activityMonitor
        self.hotkeyManager       = hotkeyManager
        self.perception          = perception
        self.automationEngine    = automationEngine
        self.companionEngine     = companionEngine
        self.tierManager         = tierManager
        self.learningSystem      = learningSystem
        self.interventionEngine  = interventionEngine
        self.rhythmTracker       = rhythmTracker
        self.permissionSecurity  = permissionSecurity
        self.audioDeviceManager  = audioDeviceManager
        self.idleProcessor       = idleProcessor

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 460),
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        configurePanel()
        setInitialPosition()

        let rootView = GlassChamberView(
            engine:              engine,
            voiceSystem:         voiceSystem,
            aiLayer:             aiLayer,
            activityMonitor:     activityMonitor,
            hotkeyManager:       hotkeyManager,
            perception:          perception,
            automationEngine:    automationEngine,
            companionEngine:     companionEngine,
            tierManager:         tierManager,
            learningSystem:      learningSystem,
            interventionEngine:  interventionEngine,
            rhythmTracker:       rhythmTracker,
            permissionSecurity:  permissionSecurity,
            audioDeviceManager:  audioDeviceManager,
            idleProcessor:       idleProcessor
        )

        let hostingView = NSHostingView(rootView: rootView)

        // The NSPanel is already opaque=false / backgroundColor=.clear, but
        // NSHostingView creates its own CALayer whose backgroundColor defaults
        // to opaque black. Without this, the panel renders with a solid black
        // background even though the SwiftUI content is transparent.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

        contentView = hostingView
    }

    // MARK: - Private setup

    private func configurePanel() {
        level              = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded   = true
        isOpaque          = false
        backgroundColor   = .clear
        hasShadow         = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    private func setInitialPosition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.maxX - 300
        let y = frame.midY - 230
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}

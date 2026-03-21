import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Module instances

    private let engine              = VisualizationEngine()
    private let voiceProfile        = VoiceProfileManager()
    private lazy var voiceSystem    = VoiceSystem(voiceProfile: voiceProfile)
    private let audioDeviceManager  = AudioDeviceManager()
    private let aiLayer             = AIIntegrationLayer()
    private let activityMonitor  = ActivityMonitor()
    private let learningSystem   = LearningSystem()
    private let hotkeyManager    = HotkeyManager()
    private let perception       = PerceptionLayer()
    private let audioDuck        = AudioDuckManager()
    private let menuBarManager   = MenuBarManager()
    private let automationEngine = AutomationEngine()
    // Phase 2 additions
    private let tierManager      = PermissionTierManager()
    private let rhythmTracker    = DailyRhythmTracker()
    // Phase 2 — Librarian (created after tierManager + activityMonitor + learningSystem)
    private lazy var idleProcessor = IdleBackgroundProcessor(
        tierManager:     tierManager,
        activityMonitor: activityMonitor,
        learningSystem:  learningSystem
    )

    private lazy var permissionSecurity = PermissionSecurityManager(
        activityMonitor: activityMonitor
    )
    private lazy var interventionEngine = InterventionEngine(
        learningSystem:     learningSystem,
        permissionSecurity: permissionSecurity,
        rhythmTracker:      rhythmTracker
    )

    /// The proactive companion loop — checks every 30s whether BUTLER should speak up.
    private lazy var companionEngine = CompanionEngine(
        activityMonitor:    activityMonitor,
        permissionSecurity: permissionSecurity,
        interventionEngine: interventionEngine,
        aiLayer:            aiLayer,
        voiceSystem:        voiceSystem,
        visualEngine:       engine,
        perception:         perception,
        tierManager:        tierManager,
        rhythmTracker:      rhythmTracker
    )

    // MARK: - Windows

    private var glassChamber:       GlassChamberPanel?
    private var birthPhaseWindow:   NSWindow?
    private var birthCoordinator:   BirthPhaseCoordinator?
    /// Observation task watching `BirthPhaseCoordinator.isComplete`.
    private var birthObserverTask:  Task<Void, Never>?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Wire audio device manager + duck manager into voice system
        voiceSystem.audioDeviceManager = audioDeviceManager
        voiceSystem.audioDuckManager   = audioDuck

        // Pre-warm CoreAudio hardware graph off main thread so the first
        // listen() call is instant (no beachball on mic button press).
        voiceSystem.prewarmAudio()

        // Wire menu bar icon to pulse state + voice system for live amplitude
        engine.onStateChange = { [weak menuBarManager] state in
            menuBarManager?.updateIcon(for: state)
        }
        menuBarManager.setVoiceSystem(voiceSystem)

        // Start context sensing
        activityMonitor.start()

        // Start perception sensors (async: calendar + screen capture permission)
        Task { await perception.start() }

        // Start proactive companion loop
        companionEngine.start()

        // Start librarian background processor (will self-gate on Tier 4 toggle)
        idleProcessor.start()

        // Start global hotkey
        hotkeyManager.start()
        hotkeyManager.onActivate = { [weak self] in
            self?.voiceSystem.activationRequested = true
        }

        // Wake/unlock → decay tolerance + recheck hotkey permission
        let wakeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        for name in wakeNames {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleWake),
                name:     name,
                object:   nil
            )
        }

        // Determine whether to show onboarding or go straight to Glass Chamber.
        //
        // IMPORTANT: warm the Swift concurrency main-actor executor BEFORE creating
        // any SwiftUI window.
        //
        // `applicationDidFinishLaunching` is a pure AppKit ObjC delegate — no Swift
        // concurrency Task is active. On macOS 26 (Swift 6 strict concurrency),
        // SwiftUI's gesture handlers call `MainActor.assumeIsolated`, which calls
        // `swift_task_isCurrentExecutorWithFlagsImpl`, which dereferences the Swift
        // concurrency main-actor executor singleton. That singleton starts as nil and
        // is initialized lazily on the first use of the Swift concurrency main actor.
        //
        // Strategy: create an async Task that yields twice on the main actor, then
        // shows the window. The two yield points ensure the Swift concurrency runtime
        // has fully registered its main-actor executor before any NSHostingView is
        // created and before AppKit's first layout pass.
        let onboardingComplete = UserDefaults.standard.bool(forKey: "butler.onboarding.complete")

        Task { @MainActor [weak self] in
            // First yield: bootstraps the main-actor executor cooperative queue.
            await Task.yield()
            // Second yield: ensures any pending runtime initialization drains.
            await Task.yield()

            guard let self else { return }
            if onboardingComplete {
                self.showGlassChamber()
            } else {
                self.showBirthPhase()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Glass Chamber

    private func showGlassChamber() {
        let panel = GlassChamberPanel(
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
        panel.makeKeyAndOrderFront(nil)
        glassChamber = panel
        menuBarManager.setPanel(panel)
    }

    // MARK: - Birth phase onboarding

    /// Shows the BUTLER birth sequence in a dedicated full-bleed window.
    ///
    /// When the coordinator sets `isComplete = true` (sequence finished or skipped),
    /// the birth window closes and the Glass Chamber appears. This is observed via
    /// a polling task since `@Observable` change tracking requires a SwiftUI body
    /// re-render or explicit `withObservationTracking`.
    private func showBirthPhase() {
        let coordinator = BirthPhaseCoordinator(
            voiceSystem:     voiceSystem,
            activityMonitor: activityMonitor,
            visualEngine:    engine
        )
        self.birthCoordinator = coordinator

        let birthView = BirthPhaseView(coordinator: coordinator, engine: engine)

        // Dark, borderless window — fills a large portion of the main screen
        guard let screen = NSScreen.main else { showGlassChamber(); return }
        let screenFrame = screen.visibleFrame
        let windowWidth:  CGFloat = 620
        let windowHeight: CGFloat = 700
        let originX = screenFrame.midX - windowWidth  / 2
        let originY = screenFrame.midY - windowHeight / 2

        let window = NSWindow(
            contentRect: NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight),
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )
        window.level                     = .floating
        window.isOpaque                  = false
        window.backgroundColor           = .clear
        window.hasShadow                 = true
        window.isReleasedWhenClosed      = false
        window.collectionBehavior        = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: birthView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.birthPhaseWindow = window

        // Poll `coordinator.isComplete` — when it flips, close the birth window
        // and open the Glass Chamber. We use `withObservationTracking` so the
        // callback fires exactly once when `isComplete` changes.
        observeBirthCompletion(coordinator: coordinator)
    }

    /// Sets up a recursive `withObservationTracking` callback that fires when
    /// `coordinator.isComplete` becomes `true`, then tears down the birth window
    /// and opens the Glass Chamber.
    ///
    /// `withObservationTracking` delivers its `onChange` closure on the same
    /// isolation context the tracking block ran on — since we run the block on
    /// `@MainActor`, the closure is also `@MainActor`-safe.
    private func observeBirthCompletion(coordinator: BirthPhaseCoordinator) {
        birthObserverTask?.cancel()
        birthObserverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Poll at 200ms — `@Observable` + `withObservationTracking` cannot
            // bridge directly to async/await without a SwiftUI view. Polling is
            // negligible overhead and keeps the code simple.
            while !Task.isCancelled {
                if coordinator.isComplete {
                    self.handleBirthComplete()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func handleBirthComplete() {
        birthObserverTask?.cancel()
        birthObserverTask = nil

        // Animate the birth window out, then show Glass Chamber.
        // NSAnimationContext completion fires on a non-isolated thread in Swift 6,
        // so we hop back to @MainActor via Task before touching actor-isolated state.
        let window = birthPhaseWindow
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            window?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                // Release the AppDelegate's coordinator reference FIRST — while the
                // birth window (and therefore its NSHostingView → BirthPhaseView) is
                // still alive and holding its own strong reference. This ensures the
                // coordinator's retain count stays > 0 throughout SwiftUI's entire
                // @Observable teardown, so observation-invalidation callbacks that
                // fire on the next run-loop cycle after the NSHostingView is released
                // never touch freed memory.
                //
                // Order matters:
                //   1. birthCoordinator = nil   ← drops AppDelegate's +1 ref
                //   2. birthPhaseWindow = nil   ← drops window's +1, releases NSHostingView
                //      → SwiftUI tears down BirthPhaseView → releases view's +1
                //      → coordinator dealloc (ref count → 0)
                //   3. showGlassChamber()
                //
                // If we nil the window first (old order), the coordinator could reach
                // ref-count 0 while @Observable teardown callbacks are still queued,
                // producing EXC_BAD_ACCESS code=1 at address=0x0 in objc_msgSend.
                self?.birthCoordinator = nil
                self?.birthPhaseWindow?.close()
                self?.birthPhaseWindow = nil
                self?.showGlassChamber()
            }
        }
    }

    // MARK: - Session boundary

    // nonisolated: NSWorkspace notifications may be delivered on a background
    // thread on macOS 26 / Swift 6.2.3 when no queue is specified. Marking the
    // @objc selector nonisolated lets the runtime call it from any thread;
    // the Task hops back to @MainActor before touching any actor-isolated state.
    @objc nonisolated private func handleWake() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.learningSystem.decayAll()
            self.rhythmTracker.decayAll()
            self.hotkeyManager.recheckPermission()
        }
    }
}

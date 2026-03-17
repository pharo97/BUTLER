import SwiftUI
import AppKit

// MARK: - AppKitTapOverlay
//
// On macOS 26 beta (25C56), SwiftUI's gesture dispatcher calls
// `MainActor.assumeIsolated` for every action closure — including Button actions
// and .onTapGesture bodies — regardless of whether they use Swift concurrency.
// This hits `swift_task_isCurrentExecutorWithFlagsImpl`, which dereferences the
// main-actor executor's isa pointer. That pointer is nil/invalid for the
// `MainActor` global executor type on this OS beta, causing EXC_BAD_ACCESS.
//
// This struct is a transparent NSView overlay that intercepts a single click
// via NSClickGestureRecognizer. AppKit gesture recognizers fire their target-action
// via ObjC message send, not through Swift concurrency's executor machinery, so
// no `assumeIsolated` is ever called. The action runs on the main thread normally.
//
// Usage: overlay an AppKitTapOverlay on top of any SwiftUI content you want to
// be clickable:
//
//   ZStack {
//       Text("Tap me")
//       AppKitTapOverlay { handleTap() }
//   }

/// Transparent NSView that intercepts a single click via AppKit's
/// NSClickGestureRecognizer, bypassing SwiftUI's gesture dispatch.
struct AppKitTapOverlay: NSViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

        let recognizer = NSClickGestureRecognizer(
            target:  context.coordinator,
            action:  #selector(Coordinator.handleClick)
        )
        recognizer.numberOfClicksRequired = 1
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        // Trampoline selector for RunLoop dispatch — see handleClick() comment.
        @objc func fireAction() { action() }

        // Dispatch via RunLoop.main.perform(#selector:) rather than calling action()
        // directly or using DispatchQueue.main.async.
        //
        // On macOS 26 beta (25C56), SwiftUI intercepts NSViewRepresentable ObjC
        // target-action callbacks through AppKitEventBindingBridge.flushActions().
        // That bridge calls swift_task_isCurrentExecutorWithFlagsImpl before dispatching
        // the closure — that check dereferences a nil/invalid isa pointer, causing
        // EXC_BAD_ACCESS (SIGSEGV at 0x0000000400000000).
        //
        // DispatchQueue.main.async requires a @Sendable closure (Swift 6 strict
        // concurrency), which the action capture does not satisfy.
        //
        // RunLoop.main.perform(#selector:target:argument:order:modes:) posts a raw
        // Objective-C perform message to the run loop — no Swift concurrency executor
        // check, no @Sendable requirement. The selector fires on the next run loop
        // turn, synchronously on the main thread, entirely through ObjC message send.
        @objc func handleClick() {
            RunLoop.main.perform(
                #selector(fireAction),
                target: self,
                argument: nil,
                order: 0,
                modes: [.common]
            )
        }
    }
}

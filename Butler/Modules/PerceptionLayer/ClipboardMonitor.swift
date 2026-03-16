import AppKit
import Foundation

// MARK: - ClipboardChange

struct ClipboardChange {
    let text:      String
    let timestamp: Date
}

// MARK: - ClipboardMonitor

/// Polls `NSPasteboard.general.changeCount` every 2 seconds.
/// When the count changes and the new content is plain text, publishes a `ClipboardChange`.
///
/// Only tracks text (ignores images, files, etc.) to stay relevant to BUTLER's context.
@MainActor
@Observable
final class ClipboardMonitor {

    // MARK: - State

    private(set) var latestChange: ClipboardChange?

    // MARK: - Private

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var pollingTask: Task<Void, Never>?

    static let pollInterval: Duration = .seconds(2)

    // MARK: - Lifecycle

    func start() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
    }

    // MARK: - Polling

    private func poll() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // Only care about plain text
        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        latestChange = ClipboardChange(text: text, timestamp: Date())
    }
}

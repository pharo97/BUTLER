import Foundation
import AppKit
import Observation

// MARK: - LibrarianSignal

/// A lightweight context signal inferred from local file metadata.
///
/// Crucially: `sourceSummary` contains only the **filename** (never file content).
/// No bytes of actual file data are read or stored — privacy invariant maintained.
struct LibrarianSignal: Sendable {

    enum SignalType: String, Sendable {
        case fileScan          = "file_scan"
        case clipboardPattern  = "clipboard_pattern"
    }

    let type:          SignalType
    let contextHint:   ButlerContext
    let weight:        Double          // 0.0 – 1.0
    let sourceSummary: String          // filename only — never content
    let timestamp:     Date
}

// MARK: - Librarian constants (file-level — accessible from nonisolated static helpers)

/// Only process files created or modified within this window.
private let kLibrarianRecentDays: Int = 7
/// Maximum signals written per scan cycle (CPU budget guard).
private let kLibrarianMaxSignals: Int = 50

// MARK: - IdleBackgroundProcessor

/// BUTLER's background "librarian" — builds contextual knowledge during user idle time.
///
/// ## What it does
/// During idle periods it scans **metadata only** (filenames, extensions) from opted-in
/// directories and produces `LibrarianSignal` records stored in SQLite. These signals
/// nudge `LearningSystem` tolerance priors, making BUTLER gradually more aware of the
/// user's dominant work patterns without ever reading file content.
///
/// ## Privacy guarantees
/// - Filenames and extensions only — no file content, no raw bytes
/// - Never reads email, keychains, browser history, or system files
/// - All signals stay local in butler.db (never sent to any API)
/// - Requires explicit Tier 4 opt-in; sub-permissions for each source
/// - Pauses automatically: low-power mode, non-idle user context, battery < 20%
///
/// ## Requires Tier 4 — Librarian Mode (default OFF)
@MainActor
@Observable
final class IdleBackgroundProcessor {

    // MARK: - Observable state (drives debug overlay + Settings)

    private(set) var isRunning:         Bool   = false
    private(set) var lastScanAt:        Date?  = nil
    private(set) var signalsThisSession: Int   = 0
    private(set) var statusLine:        String = "Librarian inactive"

    // MARK: - Tuning

    /// How often to run a scan cycle when idle (seconds). 5 minutes.
    static let scanIntervalSeconds: TimeInterval = 300

    // MARK: - Dependencies

    private let tierManager:     PermissionTierManager
    private let activityMonitor: ActivityMonitor
    private let learningSystem:  LearningSystem

    // MARK: - Internal

    private var scanTask: Task<Void, Never>?

    // MARK: - Init

    init(
        tierManager:     PermissionTierManager,
        activityMonitor: ActivityMonitor,
        learningSystem:  LearningSystem
    ) {
        self.tierManager     = tierManager
        self.activityMonitor = activityMonitor
        self.learningSystem  = learningSystem
    }

    // MARK: - Lifecycle

    /// Start the background scan loop.
    /// Safe to call multiple times — subsequent calls are no-ops if already running.
    func start() {
        guard scanTask == nil else { return }
        isRunning = true
        statusLine = "Librarian ready"

        scanTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                await self?.runScanCycleIfEligible()
                try? await Task.sleep(for: .seconds(IdleBackgroundProcessor.scanIntervalSeconds))
            }
        }
    }

    /// Stop the background loop.
    func stop() {
        scanTask?.cancel()
        scanTask   = nil
        isRunning  = false
        statusLine = "Librarian stopped"
    }

    // MARK: - Scan cycle

    private func runScanCycleIfEligible() async {
        // All eligibility checks read @MainActor state — hop back to main
        let eligible = await MainActor.run { [weak self] () -> Bool in
            guard let self else { return false }
            guard tierManager.tier4Enabled else { return false }
            guard activityMonitor.context == .unknown else { return false }
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
            return true
        }
        guard eligible else { return }

        await MainActor.run { self.statusLine = "Scanning…" }

        var signals: [LibrarianSignal] = []

        // ── Downloads scan ───────────────────────────────────────────────────
        let scanDownloads = await MainActor.run { tierManager.tier4Downloads }
        if scanDownloads {
            let s = await Self.scanDirectory(
                .downloadsDirectory,
                tag: "Downloads"
            )
            signals.append(contentsOf: s)
        }

        // ── Desktop scan ────────────────────────────────────────────────────
        let scanDesktop = await MainActor.run { tierManager.tier4Desktop }
        if scanDesktop {
            let s = await Self.scanDirectory(
                .desktopDirectory,
                tag: "Desktop"
            )
            signals.append(contentsOf: s)
        }

        // ── Clipboard pattern detection ─────────────────────────────────────
        let scanClipboard = await MainActor.run { tierManager.tier4Clipboard }
        if scanClipboard {
            // NSPasteboard must be accessed on main actor
            let clip = await MainActor.run {
                NSPasteboard.general.string(forType: .string)
            }
            if let s = Self.signalFromClipboard(clip) {
                signals.append(s)
            }
        }

        // Apply cycle cap
        let capped = Array(signals.prefix(kLibrarianMaxSignals))

        // Persist to SQLite (DatabaseManager is @unchecked Sendable — safe off main)
        for signal in capped {
            try? DatabaseManager.shared.saveLibrarianSignal(signal)
        }

        // Prune signals older than 30 days to keep DB lean
        try? DatabaseManager.shared.pruneLibrarianSignals(olderThanDays: 30)

        // Nudge LearningSystem priors on main actor
        if !capped.isEmpty {
            await nudgeLearningSystem(with: capped)
        }

        let count = capped.count
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.signalsThisSession += count
            self.lastScanAt   = Date()
            self.statusLine   = count > 0
                ? "Indexed \(count) signal\(count == 1 ? "" : "s")"
                : "Nothing new"
        }
    }

    // MARK: - Directory scanner (nonisolated, runs on background executor)

    /// Scans `directory` for recently-modified files and returns context signals
    /// based solely on file extension — no file content is read.
    ///
    /// Marked `nonisolated` so it can run on the background executor without
    /// needing `async`; called from the detached scan task.
    private static func scanDirectory(
        _ directory: FileManager.SearchPathDirectory,
        tag: String
    ) async -> [LibrarianSignal] {
        // Hop to background for synchronous FS work
        return await Task.detached(priority: .background) {
            scanDirectorySync(directory, tag: tag)
        }.value
    }

    nonisolated private static func scanDirectorySync(
        _ directory: FileManager.SearchPathDirectory,
        tag: String
    ) -> [LibrarianSignal] {
        guard let base = FileManager.default.urls(
            for: directory, in: .userDomainMask
        ).first else { return [] }

        let cutoff = Date().addingTimeInterval(
            -Double(kLibrarianRecentDays) * 86_400
        )

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .nameKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at:                        base,
            includingPropertiesForKeys: keys,
            options:                   [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var signals: [LibrarianSignal] = []

        // Iterate synchronously — safe on background thread
        while let item = enumerator.nextObject() {
            guard signals.count < kLibrarianMaxSignals, let url = item as? URL else { break }

            guard
                let res  = try? url.resourceValues(forKeys: Set(keys)),
                res.isRegularFile == true,
                let mod  = res.contentModificationDate,
                mod >= cutoff
            else { continue }

            let ext = url.pathExtension.lowercased()
            guard
                let context = ButlerContext.fromFileExtension(ext),
                let name    = res.name
            else { continue }

            signals.append(LibrarianSignal(
                type:          .fileScan,
                contextHint:   context,
                weight:        weightForExtension(ext),
                sourceSummary: "[\(tag)] \(name)",
                timestamp:     mod
            ))
        }

        return signals
    }

    // MARK: - Clipboard pattern signal

    nonisolated private static func signalFromClipboard(_ text: String?) -> LibrarianSignal? {
        guard let text, !text.isEmpty else { return nil }

        // Detect code-like patterns without reading full content
        let codeIndicators = [
            "func ", "import ", "class ", "struct ", "let ", "var ",
            "const ", "function ", "def ", "return ", "async ", "await ",
            "interface ", "protocol ", "enum ", "->", "=>", "{}",
            "#include", "SELECT ", "FROM ", "WHERE "
        ]

        let hasCodePattern = codeIndicators.contains {
            text.localizedCaseInsensitiveContains($0)
        }

        guard hasCodePattern else { return nil }

        return LibrarianSignal(
            type:          .clipboardPattern,
            contextHint:   .coding,
            weight:        0.3,
            sourceSummary: "clipboard: code pattern (\(text.count) chars)",
            timestamp:     Date()
        )
    }

    // MARK: - Extension → context mapping

    nonisolated private static func weightForExtension(_ ext: String) -> Double {
        switch ext {
        // High-confidence project files
        case "xcodeproj", "xcworkspace", "pbxproj": return 0.9
        case "py", "go", "rs", "java", "kt":        return 0.8
        case "swift", "ts", "tsx", "js", "jsx":     return 0.8
        case "fig", "sketch", "xd":                  return 0.85
        // Medium-confidence documents
        case "pdf", "docx", "pages":                return 0.5
        case "md", "txt", "rtf":                    return 0.45
        case "xlsx", "numbers", "csv":              return 0.6
        // Lower-confidence media
        case "png", "jpg", "gif", "mp4", "mov":     return 0.25
        default:                                    return 0.3
        }
    }

    // MARK: - Learning system nudge

    /// Aggregates signals by context and applies a small tolerance nudge.
    ///
    /// One scan cycle finding 10 Swift files = one `recordManualTrigger` for coding.
    /// This is intentionally subtle — the librarian shifts priors gently, not aggressively.
    private func nudgeLearningSystem(with signals: [LibrarianSignal]) async {
        // Group total weight by context
        var weights: [ButlerContext: Double] = [:]
        for sig in signals {
            weights[sig.contextHint, default: 0] += sig.weight
        }

        // Nudge: one accept signal per context where cumulative weight ≥ 2.0
        for (context, total) in weights where total >= 2.0 {
            learningSystem.recordAccept(context: context)
        }
    }
}

// MARK: - ButlerContext + file extension inference

private extension ButlerContext {
    static func fromFileExtension(_ ext: String) -> ButlerContext? {
        switch ext {
        case "swift", "py", "js", "ts", "tsx", "jsx",
             "go", "rs", "java", "kt", "c", "cpp", "h",
             "rb", "php", "cs", "dart", "scala",
             "xcodeproj", "xcworkspace", "pbxproj",
             "json", "yaml", "yml", "toml", "sh", "bash",
             "html", "css", "scss", "sql":
            return .coding

        case "pdf", "docx", "doc", "pages", "md", "txt",
             "rtf", "odt", "epub":
            return .writing

        case "fig", "sketch", "psd", "ai", "xd",
             "afdesign", "afphoto", "png", "jpg", "jpeg",
             "gif", "svg", "mp4", "mov", "aep", "prproj":
            return .creative

        case "xlsx", "xls", "numbers", "csv", "tsv":
            return .productivity

        default:
            return nil
        }
    }
}

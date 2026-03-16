import Foundation
import AppKit

// MARK: - MemoryWriter

/// Writes and reads evolving human-readable memory files about the user.
///
/// Files live at ~/Library/Application Support/Butler/Memory/
/// Each category maps to a dedicated plaintext file named after the user.
///
/// Thread-safety: all public methods are safe to call from any actor.
/// The `NSLock` serialises the one mutable resource (file appends on the
/// same path). `UserDefaults` reads are already thread-safe. Declared
/// `@unchecked Sendable` because `NSLock`-guarded mutable state is safe
/// but cannot be statically verified by the compiler.
final class MemoryWriter: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = MemoryWriter()

    // MARK: - Directory

    private let memoryDir: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Butler/Memory", isDirectory: true)
    }()

    /// Serialises all file-append operations so concurrent calls from different
    /// actors cannot interleave writes to the same file.
    private let writeLock = NSLock()

    private init() {
        try? FileManager.default.createDirectory(
            at: memoryDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - User name

    /// Resolves the user-facing name used in file naming.
    /// Falls back to macOS full name first component, then "User".
    var userName: String {
        let stored = UserDefaults.standard.string(forKey: "butler.user.name") ?? ""
        if !stored.trimmingCharacters(in: .whitespaces).isEmpty { return stored }
        let system = NSFullUserName().components(separatedBy: " ").first ?? ""
        return system.isEmpty ? "User" : system
    }

    // MARK: - File paths

    func filePath(for category: MemoryCategory) -> URL {
        let base = userName
        switch category {
        case .personal:   return memoryDir.appendingPathComponent("\(base).txt")
        case .projects:   return memoryDir.appendingPathComponent("\(base)_Projects.txt")
        case .habits:     return memoryDir.appendingPathComponent("\(base)_Habits.txt")
        case .technical:  return memoryDir.appendingPathComponent("\(base)_Technical.txt")
        }
    }

    // MARK: - Append a single fact

    /// Appends a timestamped bullet to the given category file.
    /// No-ops if Memory Palace is disabled or the fact string is blank.
    func appendFact(_ fact: String, to category: MemoryCategory) {
        guard isEnabled else { return }
        let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let path      = filePath(for: category)
        let timestamp = Self.dateFormatter.string(from: Date())
        let line      = "[\(timestamp)] \u{2022} \(trimmed)\n"
        let name      = userName  // capture before lock to avoid re-entrant property access

        writeLock.lock()
        defer { writeLock.unlock() }

        if let handle = try? FileHandle(forWritingTo: path) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            // File does not exist yet — create with a header
            let header = """
            # \(category.displayName) — \(name)
            # Created \(timestamp)
            # Butler Memory Palace — human-readable, local only

            """
            let full = header + line
            try? full.write(to: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Append multiple facts

    func appendFacts(_ facts: [String], to category: MemoryCategory) {
        facts.forEach { appendFact($0, to: category) }
    }

    // MARK: - Read full file

    /// Returns the entire content of a category file, or nil if it does not exist.
    func readFile(for category: MemoryCategory) -> String? {
        guard isEnabled else { return nil }
        return try? String(contentsOf: filePath(for: category), encoding: .utf8)
    }

    // MARK: - Recent facts

    /// Returns the last `limit` bullet lines from a single category.
    func recentFacts(from category: MemoryCategory, limit: Int = 20) -> [String] {
        guard let content = readFile(for: category) else { return [] }
        let bullets = content
            .components(separatedBy: "\n")
            .filter { $0.contains("\u{2022} ") }
        return Array(bullets.suffix(limit))
    }

    // MARK: - All recent facts (for prompt injection)

    /// Concatenates the most recent facts from all categories into a
    /// single block suitable for injecting into a system prompt.
    func allRecentFacts(limit: Int = 30) -> String {
        let perCategory = max(1, limit / MemoryCategory.allCases.count)
        let all = MemoryCategory.allCases.flatMap {
            recentFacts(from: $0, limit: perCategory)
        }
        guard !all.isEmpty else { return "" }
        return "USER MEMORY (from Memory Palace):\n" + all.joined(separator: "\n")
    }

    // MARK: - Wipe all

    /// Deletes every memory file. Irreversible — caller must confirm with user first.
    func wipeAll() {
        MemoryCategory.allCases.forEach { cat in
            try? FileManager.default.removeItem(at: filePath(for: cat))
        }
    }

    // MARK: - Finder / editor integration

    /// Opens the Memory directory in Finder.
    func revealInFinder() {
        NSWorkspace.shared.open(memoryDir)
    }

    /// Opens the file for a specific category in the system's default text editor.
    /// Creates the file first if it does not exist so the editor launches cleanly.
    func openFile(for category: MemoryCategory) {
        let path = filePath(for: category)
        if !FileManager.default.fileExists(atPath: path.path) {
            appendFact("Memory file initialised.", to: category)
        }
        NSWorkspace.shared.open(path)
    }

    // MARK: - Persisted toggles

    /// Master switch — when false, no facts are written and no files are read.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "butler.memory.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "butler.memory.enabled") }
    }

    /// When true, `allRecentFacts` is injected into every system prompt.
    var includeInPrompts: Bool {
        get { UserDefaults.standard.bool(forKey: "butler.memory.includeInPrompts") }
        set { UserDefaults.standard.set(newValue, forKey: "butler.memory.includeInPrompts") }
    }

    // MARK: - Private

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

// MARK: - MemoryCategory

enum MemoryCategory: String, CaseIterable {
    case personal  = "personal"
    case projects  = "projects"
    case habits    = "habits"
    case technical = "technical"

    var displayName: String {
        switch self {
        case .personal:  "Personal Profile"
        case .projects:  "Projects"
        case .habits:    "Habits & Patterns"
        case .technical: "Technical Preferences"
        }
    }

    /// SF Symbol name for use in Settings UI.
    var symbolName: String {
        switch self {
        case .personal:  "person.circle"
        case .projects:  "folder"
        case .habits:    "chart.bar"
        case .technical: "gearshape"
        }
    }
}

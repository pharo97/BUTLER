import Foundation

// MARK: - SentenceChunker

/// Splits a raw LLM token stream into speakable sentences.
///
/// The core insight: LLMs stream token-by-token, but TTS needs complete
/// phrases. This chunker buffers incoming tokens and emits a sentence as
/// soon as it detects a natural boundary — so BUTLER can start speaking
/// sentence 1 while Claude is still generating sentence 2.
///
/// Boundary rules:
///   • Split on `.`, `!`, `?` followed by a space (or end of buffer)
///   • Minimum 15 chars before first split — avoids "Mr. ", "Dr. ", "U.S. "
///   • Decimal numbers (e.g. "2.0", "3.14") do NOT trigger a split
///   • Flush() emits whatever is left when the stream ends
///
/// Usage:
/// ```swift
/// var chunker = SentenceChunker()
/// for token in tokenStream {
///     for sentence in chunker.feed(token) { speak(sentence) }
/// }
/// if let last = chunker.flush() { speak(last) }
/// ```
struct SentenceChunker {

    private var buffer: String = ""

    /// Minimum chars that must precede a split point.
    private static let minimumLength: Int = 15

    // MARK: - Public API

    /// Feed a raw token. Returns any complete sentences that became available.
    mutating func feed(_ token: String) -> [String] {
        buffer += token
        return drainAll()
    }

    /// Call at end-of-stream. Returns any remaining text (last sentence fragment).
    mutating func flush() -> String? {
        let s = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return s.isEmpty ? nil : s
    }

    // MARK: - Private extraction

    private mutating func drainAll() -> [String] {
        var results: [String] = []
        while let sentence = extractFirst() {
            results.append(sentence)
        }
        return results
    }

    private mutating func extractFirst() -> String? {
        // Don't search unless we have enough chars
        guard buffer.count > Self.minimumLength else { return nil }

        let startSearch = buffer.index(buffer.startIndex, offsetBy: Self.minimumLength)
        var idx = startSearch

        while idx < buffer.endIndex {
            let ch = buffer[idx]

            if ch == "." || ch == "!" || ch == "?" {

                // Skip decimal numbers — don't split on "3.14" or "2.0"
                if ch == "." {
                    let prevIdx = buffer.index(before: idx)
                    if buffer[prevIdx].isNumber {
                        idx = buffer.index(after: idx)
                        continue
                    }
                }

                // Need to see what follows the punctuation
                let nextIdx = buffer.index(after: idx)

                // At the very end of buffer — wait for the next token
                // (we don't know if a space is coming)
                guard nextIdx < buffer.endIndex else { return nil }

                let nextCh = buffer[nextIdx]

                // Boundary confirmed: punctuation followed by whitespace
                if nextCh == " " || nextCh == "\n" || nextCh == "\r" {
                    let sentence = String(buffer[buffer.startIndex...idx])
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // Advance buffer past the whitespace character
                    let afterSpace = buffer.index(after: nextIdx)
                    buffer = afterSpace < buffer.endIndex
                        ? String(buffer[afterSpace...])
                        : ""

                    return sentence.isEmpty ? nil : sentence
                }
            }

            idx = buffer.index(after: idx)
        }

        return nil
    }
}

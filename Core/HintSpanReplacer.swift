import Foundation

/// Applies hint word replacements to the model's own text, so only the replaced words change. Each span keeps its
/// own leading quotes or brackets and trailing punctuation; everything outside the spans stays byte for byte.
public enum HintSpanReplacer {
    public struct Replacement: Equatable, Sendable {
        /// The model's words as the rescorer saw them: separated by single spaces, punctuation attached.
        public var original: String
        public var replacement: String

        public init(original: String, replacement: String) {
            self.original = original
            self.replacement = replacement
        }
    }

    /// Nil when a span isn't in `text` as whole words. Spans may come in any order; a repeated span takes the
    /// next occurrence not already replaced.
    public static func apply(_ replacements: [Replacement], to text: String) -> String? {
        var edits: [(range: Range<String.Index>, with: String)] = []
        for replacement in replacements {
            guard let range = wholeWordRange(of: replacement.original, in: text, avoiding: edits.map(\.range))
            else { return nil }
            edits.append((range, affixed(replacement.replacement, like: replacement.original)))
        }
        var result = ""
        var cursor = text.startIndex
        for edit in edits.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            result += text[cursor..<edit.range.lowerBound]
            result += edit.with
            cursor = edit.range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// The first occurrence bounded by whitespace or the ends of `text` that overlaps none of `taken`.
    private static func wholeWordRange(
        of span: String, in text: String, avoiding taken: [Range<String.Index>]
    ) -> Range<String.Index>? {
        guard !span.isEmpty else { return nil }
        var start = text.startIndex
        while start < text.endIndex, let found = text[start...].firstRange(of: span) {
            let opens = found.lowerBound == text.startIndex || text[text.index(before: found.lowerBound)].isWhitespace
            let closes = found.upperBound == text.endIndex || text[found.upperBound].isWhitespace
            if opens, closes, !taken.contains(where: { $0.overlaps(found) }) { return found }
            start = text.index(after: found.lowerBound)
        }
        return nil
    }

    /// `replacement` wrapped in the punctuation `original` opens and closes with.
    private static func affixed(_ replacement: String, like original: String) -> String {
        let leading = original.prefix(while: \.isPunctuation)
        let trailing = original.dropFirst(leading.count).reversed().prefix(while: \.isPunctuation).reversed()
        return leading + replacement + String(trailing)
    }
}

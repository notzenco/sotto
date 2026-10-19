import Foundation

/// Fits a dictation to the text already before the cursor, so back-to-back dictations read as one passage.
public enum InsertJoin {
    /// `before` is the text just before the cursor, or nil when the app does not expose it.
    /// `keepsCapital` protects a capitalised first word, such as a name, from being lowercased mid-sentence.
    public static func fit(_ text: String, before: String?, mode: DictationMode,
                           keepsCapital: (String) -> Bool = { _ in false }) -> String {
        guard let before, let last = before.last, let first = text.first else { return text }
        var fitted = text
        if mode == .prose, continuesSentence(before) {
            fitted = lowercasingFirstWord(fitted, keepsCapital: keepsCapital)
        }
        if needsSpace(before, last: last), !first.isWhitespace, !leadingPunctuation.contains(first) {
            fitted = " " + fitted
        }
        return fitted
    }

    private static let leadingPunctuation: Set<Character> = [".", ",", "!", "?", ":", ";", ")", "]", "}", "…"]
    private static let opening: Set<Character> = ["(", "[", "{", "/", "\\", "@", "#", "_", "$", "“", "‘"]
    private static let sentenceEnd: Set<Character> = [".", "!", "?", "…"]

    private static func needsSpace(_ before: String, last: Character) -> Bool {
        if last.isWhitespace || opening.contains(last) { return false }
        let afterText = before.dropLast().last.map { !$0.isWhitespace } ?? false
        // A straight quote closes after text and opens after a space.
        if last == "\"" || last == "'" { return afterText }
        // A dash after a space is punctuation; after text it is a hyphen.
        if last == "-" { return !afterText }
        return true
    }

    private static func continuesSentence(_ before: String) -> Bool {
        guard let index = before.lastIndex(where: { !$0.isWhitespace }) else { return false }
        if before[before.index(after: index)...].contains(where: \.isNewline) { return false }
        let last = before[index]
        return last.isLetter || last.isNumber || last == "," || last == ";"
    }

    private static func lowercasingFirstWord(_ text: String, keepsCapital: (String) -> Bool) -> String {
        guard let start = text.firstIndex(where: { $0.isLetter || $0.isNumber || $0.isNewline || sentenceEnd.contains($0) }),
              text[start].isUppercase else { return text }
        let end = text[start...].firstIndex { !($0.isLetter || $0 == "'" || $0 == "’") } ?? text.endIndex
        let word = String(text[start..<end])
        if word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") { return text }
        if word.filter(\.isUppercase).count > 1 || keepsCapital(word) { return text }
        return String(text[..<start]) + text[start].lowercased() + String(text[text.index(after: start)...])
    }
}

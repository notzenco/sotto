import Foundation

/// Respells prose word by word between American, British and Australian
/// English, leaving anything that looks like code alone.
public enum SpellingConverter {
    /// Credit for the bundled word list, which its licence asks About to show.
    public static let credit: String? = "Spelling list adapted from VarCon by Kevin Atkinson and Benjamin Titze, from word lists by Geoff Kuenning. Copyright 2000-2019 Kevin Atkinson, 2016 Benjamin Titze, 1993 Geoff Kuenning. Modified: a subset of common words."

    public static func convert(_ text: String, to variety: SpellingVariety) -> String {
        let table = switch variety {
        case .australian: australian
        case .british: SpellingTable.americanToBritish
        case .american: american
        }
        var output = ""
        var chunk = ""
        var inBackticks = false
        for character in text {
            if character == "`" {
                output += respell(chunk, with: table)
                chunk = ""
                inBackticks.toggle()
                output.append(character)
            } else if inBackticks {
                output.append(character)
            } else if character.isWhitespace {
                output += respell(chunk, with: table)
                chunk = ""
                output.append(character)
            } else {
                chunk.append(character)
            }
        }
        return output + respell(chunk, with: table)
    }

    private static let australian = SpellingTable.americanToBritish.filter {
        !SpellingTable.australianKeeps.contains($0.key)
    }

    // The generator only keeps pairs that are unambiguous both ways, so
    // every British spelling maps back to exactly one American one.
    private static let american = Dictionary(
        SpellingTable.americanToBritish.map { ($0.value, $0.key) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Respells the words in one whitespace-free chunk, keeping its punctuation.
    private static func respell(_ chunk: String, with table: [String: String]) -> String {
        guard !chunk.isEmpty, !looksLikeCode(chunk) else { return chunk }
        var output = ""
        var word = ""
        for character in chunk {
            if character.isLetter {
                word.append(character)
            } else {
                output += respellWord(word, with: table)
                word = ""
                output.append(character)
            }
        }
        return output + respellWord(word, with: table)
    }

    /// Matches case as lower or Capitalised; any other casing, including
    /// all caps, is left unchanged.
    private static func respellWord(_ word: String, with table: [String: String]) -> String {
        let lower = word.lowercased()
        guard let target = table[lower] else { return word }
        if word == lower { return target }
        if word.dropFirst() == lower.dropFirst(), word.first?.isUppercase == true {
            return target.prefix(1).uppercased() + target.dropFirst()
        }
        return word
    }

    /// Paths, URLs, snake_case, camelCase, dotted names such as file.color,
    /// flags, tags, variables, handles and anything with a digit.
    private static func looksLikeCode(_ chunk: String) -> Bool {
        if chunk.contains(where: { $0 == "_" || $0 == "/" || $0 == "\\" || $0.isNumber }) { return true }
        if ["--", "#", "$", "@"].contains(where: chunk.hasPrefix) { return true }
        var previous: Character?
        var beforePrevious: Character?
        for character in chunk {
            if let previous, previous.isLowercase, character.isUppercase { return true }
            if let beforePrevious, let previous, previous == ".", beforePrevious.isLetter, character.isLetter {
                return true
            }
            beforePrevious = previous
            previous = character
        }
        return false
    }
}

import Foundation

public enum TranscriptFormatter {
    public static func format(_ raw: String, mode: DictationMode) -> String {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return "" }
        let phrases = mode == .prose ? prosePhrases : literalPhrases
        let fillers = mode == .prose ? proseFillers : []
        var atoms: [Atom] = []
        var index = 0
        while index < tokens.count {
            if let phrase = matchPhrase(tokens, at: index, phrases: phrases) {
                atoms.append(phrase.atom)
                index += phrase.words.count
                continue
            }
            let token = tokens[index]
            let lower = token.lowercased()
            if fillers.contains(lower) {
                index += 1
                continue
            }
            if mode == .literal, lower == "word", index + 1 < tokens.count,
               matchPhrase(tokens, at: index + 1, phrases: literalPhrases) != nil
            {
                atoms.append(.text(tokens[index + 1]))
                index += 2
                continue
            }
            if let existing = punctuationAtom(token) {
                atoms.append(existing)
            } else {
                atoms.append(.text(token))
            }
            index += 1
        }
        let rendered = render(atoms).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rendered.isEmpty else { return "" }
        return mode == .prose ? capitalizeSentences(rendered) : rendered
    }

    private struct Phrase {
        var words: [String]
        var atom: Atom
    }

    private enum Atom {
        case text(String)
        case tight(String)
        case trail(String)
        case line(Int)
    }

    private static let proseFillers: Set<String> = ["um", "uh", "er", "ah", "hmm"]

    private static let prosePhrases: [Phrase] = [
        Phrase(words: ["exclamation", "point"], atom: .trail("!")),
        Phrase(words: ["exclamation", "mark"], atom: .trail("!")),
        Phrase(words: ["question", "mark"], atom: .trail("?")),
        Phrase(words: ["new", "paragraph"], atom: .line(2)),
        Phrase(words: ["new", "line"], atom: .line(1)),
        Phrase(words: ["full", "stop"], atom: .trail(".")),
        Phrase(words: ["period"], atom: .trail(".")),
        Phrase(words: ["comma"], atom: .trail(",")),
        Phrase(words: ["colon"], atom: .trail(":")),
        Phrase(words: ["semicolon"], atom: .trail(";")),
        Phrase(words: ["newline"], atom: .line(1)),
    ]

    private static let literalPhrases: [Phrase] = [
        Phrase(words: ["exclamation", "point"], atom: .trail("!")),
        Phrase(words: ["question", "mark"], atom: .trail("?")),
        Phrase(words: ["open", "paren"], atom: .tight("(")),
        Phrase(words: ["close", "paren"], atom: .tight(")")),
        Phrase(words: ["open", "bracket"], atom: .tight("[")),
        Phrase(words: ["close", "bracket"], atom: .tight("]")),
        Phrase(words: ["open", "brace"], atom: .tight("{")),
        Phrase(words: ["close", "brace"], atom: .tight("}")),
        Phrase(words: ["at", "sign"], atom: .tight("@")),
        Phrase(words: ["pound", "sign"], atom: .tight("#")),
        Phrase(words: ["new", "line"], atom: .line(1)),
        Phrase(words: ["dot"], atom: .tight(".")),
        Phrase(words: ["slash"], atom: .tight("/")),
        Phrase(words: ["backslash"], atom: .tight("\\")),
        Phrase(words: ["underscore"], atom: .tight("_")),
        Phrase(words: ["dash"], atom: .tight("-")),
        Phrase(words: ["hyphen"], atom: .tight("-")),
        Phrase(words: ["colon"], atom: .trail(":")),
        Phrase(words: ["semicolon"], atom: .trail(";")),
        Phrase(words: ["comma"], atom: .trail(",")),
        Phrase(words: ["hash"], atom: .tight("#")),
        Phrase(words: ["plus"], atom: .tight("+")),
        Phrase(words: ["equals"], atom: .tight("=")),
        Phrase(words: ["quote"], atom: .tight("\"")),
    ]

    private static func matchPhrase(_ tokens: [String], at index: Int, phrases: [Phrase]) -> Phrase? {
        for phrase in phrases where index + phrase.words.count <= tokens.count {
            let slice = tokens[index..<(index + phrase.words.count)].map { $0.lowercased() }
            if slice == phrase.words { return phrase }
        }
        return nil
    }

    private static func punctuationAtom(_ token: String) -> Atom? {
        switch token {
        case ".", "!", "?", ",", ";", ":":
            .trail(token)
        case "_", "/", "-", "\\":
            .tight(token)
        default:
            nil
        }
    }

    private static func render(_ atoms: [Atom]) -> String {
        var output = ""
        var suppressSpace = true
        for atom in atoms {
            switch atom {
            case .text(let text):
                if !suppressSpace, !output.isEmpty, !output.hasSuffix("\n") {
                    output.append(" ")
                }
                output.append(text)
                suppressSpace = false
            case .tight(let symbol):
                output.append(symbol)
                suppressSpace = true
            case .trail(let symbol):
                output.append(symbol)
                suppressSpace = false
            case .line(let count):
                while output.hasSuffix(" ") { output.removeLast() }
                output.append(String(repeating: "\n", count: count))
                suppressSpace = true
            }
        }
        return output
    }

    private static func capitalizeSentences(_ text: String) -> String {
        var characters = Array(text)
        var shouldCapitalize = true
        for index in characters.indices {
            let character = characters[index]
            if character.isNewline {
                shouldCapitalize = true
                continue
            }
            if character.isWhitespace { continue }
            if shouldCapitalize, character.isLetter {
                let upper = String(character).uppercased()
                if let first = upper.first {
                    characters[index] = first
                }
                shouldCapitalize = false
            } else if character.isLetter || character.isNumber {
                shouldCapitalize = false
            }
            if character == "." || character == "!" || character == "?" {
                shouldCapitalize = true
            }
        }
        return String(characters)
    }
}

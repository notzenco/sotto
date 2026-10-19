import Foundation

/// Whether two phrases sound alike, so a fix such as "Margie" → "my G" counts and rewording doesn't.
public enum SoundAlike {
    public static func similar(_ a: String, _ b: String) -> Bool {
        let first = key(a), second = key(b)
        guard !first.isEmpty, !second.isEmpty else { return false }
        let longest = max(first.count, second.count)
        // Similar when at most a third of the longer phonetic key has to change.
        return Double(distance(first, second)) <= Double(longest) / 3
    }

    /// A simplified Metaphone key with a non-rhotic "r", read across word breaks.
    /// Single letters are spelled out ("g" → "jee"), so "my g" keys like "Madgie".
    static func key(_ phrase: String) -> String {
        let words = phrase.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !(("a"..."z").contains($0) || $0.isNumber) }
        let letters = Array(words.map { $0.count == 1 ? letterNames[String($0)] ?? String($0) : String($0) }.joined())

        func at(_ index: Int) -> Character? { letters.indices.contains(index) ? letters[index] : nil }
        func isVowel(_ index: Int) -> Bool { at(index).map { "aeiouy".contains($0) } ?? false }
        func isSoftening(_ index: Int) -> Bool { at(index).map { "eiy".contains($0) } ?? false }

        var sounds: [Character] = []
        var index = 0
        while index < letters.count {
            let letter = letters[index], next = at(index + 1)
            var sound: String
            var width = 1
            switch letter {
            case "a", "e", "i", "o", "u":
                sound = index == 0 ? "a" : ""
            case "y", "w":
                sound = isVowel(index + 1) ? String(letter) : ""
            case "h":
                sound = isVowel(index + 1) && (index == 0 || isVowel(index - 1)) ? "h" : ""
            case "c":
                if next == "h" { sound = "x"; width = 2 } else { sound = isSoftening(index + 1) ? "s" : "k" }
            case "d":
                if next == "g", isSoftening(index + 2) { sound = "j"; width = 2 } else { sound = "t" }
            case "g":
                if next == "h" { sound = index == 0 ? "k" : ""; width = 2 } else { sound = isSoftening(index + 1) ? "j" : "k" }
            case "k":
                sound = index == 0 && next == "n" ? "" : "k"
            case "p":
                if next == "h" { sound = "f"; width = 2 } else { sound = "p" }
            case "s":
                if next == "h" { sound = "x"; width = 2 } else { sound = "s" }
            case "t":
                if next == "h" { sound = "0"; width = 2 } else { sound = "t" }
            case "r":
                // Australian English drops an "r" that no vowel follows: "Margie" sounds like "Mahjee".
                sound = isVowel(index + 1) ? "r" : ""
            case "q": sound = "k"
            case "v": sound = "f"
            case "x": sound = index == 0 ? "s" : "ks"
            case "z": sound = "s"
            default: sound = String(letter)
            }
            for character in sound where character != sounds.last { sounds.append(character) }
            index += width
        }
        return String(sounds)
    }

    private static let letterNames: [String: String] = [
        "a": "ay", "b": "bee", "c": "see", "d": "dee", "e": "ee", "f": "ef", "g": "jee", "h": "aitch",
        "i": "eye", "j": "jay", "k": "kay", "l": "el", "m": "em", "n": "en", "o": "oh", "p": "pee",
        "q": "cue", "r": "ar", "s": "ess", "t": "tee", "u": "you", "v": "vee", "w": "doubleyou",
        "x": "ex", "y": "why", "z": "zed",
    ]

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1..<a.count + 1 {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1..<b.count + 1 {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

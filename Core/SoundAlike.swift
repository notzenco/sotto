import Foundation

/// Whether two phrases sound alike, so a fix such as "Margie" → "my G" counts and rewording doesn't.
public enum SoundAlike {
    public static func similar(_ a: String, _ b: String) -> Bool {
        if isInflection(a, b) { return false }
        let first = key(a), second = key(b)
        guard !first.isEmpty, !second.isEmpty else { return false }
        let longest = max(first.count, second.count)
        // Keys of up to 3 sounds must match exactly; longer ones may differ in up to a third of their sounds.
        return longest <= 3 ? first == second : Double(distance(first, second)) <= Double(longest) / 3
    }

    /// A simplified Metaphone key that keeps a coarse vowel for each vowel group, with a non-rhotic "r".
    /// Single letters are spelled out ("g" → "jee"), so "my g" (`myje`) keys close to "Madgie" and "Maggie" (`maje`).
    static func key(_ phrase: String) -> String {
        var sounds: [Character] = []
        for word in words(phrase) {
            let spelled = word.count == 1 ? letterNames[word] ?? word : word
            for sound in wordKey(Array(spelled)) where sound != sounds.last { sounds.append(sound) }
        }
        return String(sounds)
    }

    /// One side is the other with an ending added (cat → cats, walk → walked, like → liked):
    /// a grammar edit, not a mishearing.
    static func isInflection(_ a: String, _ b: String) -> Bool {
        let left = words(a), right = words(b)
        guard left.count == right.count, left != right else { return false }
        return zip(left, right).allSatisfy { $0 == $1 || inflects($0, $1) }
    }

    private static func words(_ phrase: String) -> [String] {
        phrase.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !(("a"..."z").contains($0) || $0.isNumber) }
            .map(String.init)
    }

    private static func inflects(_ a: String, _ b: String) -> Bool {
        let (stem, longer) = a.count <= b.count ? (a, b) : (b, a)
        guard let last = stem.last else { return false }
        for ending in ["s", "es", "d", "ed", "ing"] {
            if longer == stem + ending || longer == stem + String(last) + ending { return true }
            if last == "e" || last == "y", longer == String(stem.dropLast()) + (last == "y" ? "i" : "") + ending { return true }
        }
        return false
    }

    private static func wordKey(_ letters: [Character]) -> String {
        func at(_ index: Int) -> Character? { letters.indices.contains(index) ? letters[index] : nil }
        func isVowelLetter(_ index: Int) -> Bool { at(index).map { "aeiouy".contains($0) } ?? false }
        func isSoftening(_ index: Int) -> Bool { at(index).map { "eiy".contains($0) } ?? false }
        // "y" is a consonant before a vowel ("yes") and a vowel otherwise ("my", "day").
        func isVowelSound(_ index: Int) -> Bool {
            guard let letter = at(index) else { return false }
            if letter == "y" { return !(at(index + 1).map { "aeiou".contains($0) } ?? false) }
            return "aeiou".contains(letter)
        }

        var sounds = ""
        var index = 0
        while index < letters.count {
            if isVowelSound(index) {
                var end = index
                while isVowelSound(end) { end += 1 }
                let group = String(letters[index..<end])
                let silentE = group == "e" && end == letters.count && letters[..<index].contains { "aeiouy".contains($0) }
                if !silentE { sounds += vowelSounds[String(group.prefix(2))] ?? String(group.prefix(1)) }
                index = end
                continue
            }
            let letter = letters[index], next = at(index + 1)
            // A doubled consonant is one sound, so "Maggie" keys like "Margie" (except "cc", as in "accept").
            if next == letter, letter != "c" { index += 1; continue }
            var width = 1
            switch letter {
            case "w":
                sounds += isVowelLetter(index + 1) ? "w" : ""
            case "h":
                sounds += isVowelLetter(index + 1) && (index == 0 || isVowelLetter(index - 1)) ? "h" : ""
            case "c":
                if next == "h" { sounds += "x"; width = 2 } else { sounds += isSoftening(index + 1) ? "s" : "k" }
            case "d":
                if next == "g", isSoftening(index + 2) { sounds += "j"; width = 2 } else { sounds += "t" }
            case "g":
                if next == "h" { sounds += index == 0 ? "k" : ""; width = 2 } else { sounds += isSoftening(index + 1) ? "j" : "k" }
            case "k":
                sounds += index == 0 && next == "n" ? "" : "k"
            case "p":
                if next == "h" { sounds += "f"; width = 2 } else { sounds += "p" }
            case "s":
                if next == "h" { sounds += "x"; width = 2 } else { sounds += "s" }
            case "t":
                if next == "h" { sounds += "0"; width = 2 } else { sounds += "t" }
            case "r":
                // Australian English drops an "r" that no vowel follows: "Margie" sounds like "Mahjee".
                sounds += isVowelLetter(index + 1) ? "r" : ""
            case "q": sounds += "k"
            case "v": sounds += "f"
            case "x": sounds += index == 0 ? "s" : "ks"
            case "z": sounds += "s"
            default: sounds += String(letter)
            }
            index += width
        }
        return sounds
    }

    /// Vowel pairs that read as one sound; any other vowel group keys as its first letter.
    private static let vowelSounds: [String: String] = [
        "ee": "e", "ea": "e", "ie": "e", "ei": "e", "ey": "e", "oo": "u", "ou": "u", "ue": "u",
    ]

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

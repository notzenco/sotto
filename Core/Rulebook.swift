import Foundation

public struct Replacement: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var heard: String
    public var written: String

    public init(id: UUID = UUID(), heard: String, written: String) {
        self.id = id
        self.heard = heard
        self.written = written
    }
}

/// Local spellings. A deleted phrase is remembered so a later "remember" does not put it back.
public struct Rulebook: Codable, Equatable, Sendable {
    public var replacements: [Replacement]
    public var deletedHeard: [String]

    public init(replacements: [Replacement] = [], deletedHeard: [String] = []) {
        self.replacements = replacements
        self.deletedHeard = deletedHeard
    }

    public func applying(to text: String) -> String {
        applying(to: text, alsoMatching: { $0 })
    }

    /// Also matches each heard form as `variant` rewrites it, such as after spelling conversion,
    /// so the owner's Names still win over respelled words.
    public func applying(to text: String, alsoMatching variant: (String) -> String) -> String {
        let rules = replacements
            .flatMap { rule -> [Replacement] in
                let heard = normalized(rule.heard)
                let converted = normalized(variant(heard))
                return (converted == heard ? [heard] : [heard, converted])
                    .map { Replacement(id: rule.id, heard: $0, written: rule.written) }
            }
            .filter { !$0.heard.isEmpty }
            .sorted { $0.heard.count > $1.heard.count }
        let source = text as NSString
        var index = 0
        var output = ""
        while index < source.length {
            if let match = firstMatch(in: source, at: index, rules: rules) {
                output += match.written
                index += match.length
            } else {
                output += source.substring(with: NSRange(location: index, length: 1))
                index += 1
            }
        }
        return output
    }

    public func remember(heard: String, written: String) -> Rulebook {
        let key = normalized(heard)
        guard !key.isEmpty else { return self }
        if deletedHeard.contains(where: { normalized($0) == key }) { return self }
        var copy = self
        copy.replacements.removeAll { normalized($0.heard) == key }
        copy.replacements.append(Replacement(heard: key, written: written))
        return copy
    }

    public func delete(id: UUID) -> Rulebook {
        guard let row = replacements.first(where: { $0.id == id }) else { return self }
        var copy = self
        copy.replacements.removeAll { $0.id == id }
        let key = normalized(row.heard)
        if !key.isEmpty, !copy.deletedHeard.contains(where: { normalized($0) == key }) {
            copy.deletedHeard.append(key)
        }
        return copy
    }

    private func normalized(_ phrase: String) -> String {
        phrase
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private func firstMatch(
        in source: NSString,
        at index: Int,
        rules: [Replacement]
    ) -> (written: String, length: Int)? {
        for rule in rules {
            if let length = matchLength(in: source, at: index, heard: rule.heard) {
                return (rule.written, length)
            }
        }
        return nil
    }

    private func matchLength(in source: NSString, at index: Int, heard: String) -> Int? {
        if index > 0, isWord(source.character(at: index - 1)) { return nil }
        let heardNS = heard as NSString
        let remaining = source.length - index
        guard remaining >= heardNS.length, heardNS.length > 0 else { return nil }
        let slice = source.substring(with: NSRange(location: index, length: heardNS.length))
        guard slice.compare(heard, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else {
            return nil
        }
        let end = index + heardNS.length
        if end < source.length, isWord(source.character(at: end)) { return nil }
        return heardNS.length
    }

    private func isWord(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }
}

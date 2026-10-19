import Foundation

public enum LearnSource: String, Codable, Sendable {
    case fix, compare, teacher
}

public struct LearnedWord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var written: String
    public var heardForms: [String]
    public var sources: [LearnSource]
    public var count: Int
    /// Clips the teacher found this word on. Each clip counts once.
    public var teacherClips: [UUID]
    public var learned: Bool

    public init(id: UUID = UUID(), written: String, heardForms: [String] = [], sources: [LearnSource] = [],
                count: Int = 0, teacherClips: [UUID] = [], learned: Bool = false) {
        self.id = id
        self.written = written
        self.heardForms = heardForms
        self.sources = sources
        self.count = count
        self.teacherClips = teacherClips
        self.learned = learned
    }
}

/// The owner's words: learned from fixes, Compare picks and the teacher, plus words typed in by hand.
/// A deleted learned word is blocked so fixes and the teacher don't learn it again.
public struct Lexicon: Codable, Equatable, Sendable {
    public var entries: [LearnedWord]
    public var yourWords: [String]
    /// Normalised written forms.
    public var blocked: [String]

    /// The teacher's pair counts once it turns up on this many different clips.
    private static let teacherClipsToLearn = 2

    public init(entries: [LearnedWord] = [], yourWords: [String] = [], blocked: [String] = []) {
        self.entries = entries
        self.yourWords = yourWords
        self.blocked = blocked
    }

    public var learnedWords: [LearnedWord] {
        entries.filter(\.learned)
    }

    /// Fixes and Compare picks learn at once; the teacher learns on its second clip.
    /// A Compare pick also unblocks a deleted word.
    public func recording(_ s: Substitution, source: LearnSource, clipID: UUID?) -> Lexicon {
        let key = Self.normalized(s.written)
        let heard = Self.normalized(s.heard)
        guard !key.isEmpty, !heard.isEmpty else { return self }
        var copy = self
        if blocked.contains(key) {
            guard source == .compare else { return self }
            copy.blocked.removeAll { $0 == key }
        }

        let index: Int
        if let found = copy.entries.firstIndex(where: { Self.normalized($0.written) == key }) {
            index = found
        } else {
            copy.entries.append(LearnedWord(written: Self.singleSpaced(s.written)))
            index = copy.entries.count - 1
        }
        var entry = copy.entries[index]
        var repeatsClip = false
        if source == .teacher, let clipID {
            repeatsClip = entry.teacherClips.contains(clipID)
            if !repeatsClip { entry.teacherClips.append(clipID) }
        }
        if !entry.heardForms.contains(heard) { entry.heardForms.append(heard) }
        if !entry.sources.contains(source) { entry.sources.append(source) }
        if !repeatsClip { entry.count += 1 }
        switch source {
        case .fix, .compare: entry.learned = true
        case .teacher: entry.learned = entry.learned || entry.teacherClips.count >= Self.teacherClipsToLearn
        }
        copy.entries[index] = entry
        return copy
    }

    /// Removes the word and blocks its written form.
    public func deleting(id: UUID) -> Lexicon {
        guard let entry = entries.first(where: { $0.id == id }) else { return self }
        var copy = self
        copy.entries.removeAll { $0.id == id }
        let key = Self.normalized(entry.written)
        if !key.isEmpty, !copy.blocked.contains(key) { copy.blocked.append(key) }
        return copy
    }

    /// Adds a hint word typed by the owner, which also unblocks it.
    public func addingYourWord(_ word: String) -> Lexicon {
        let key = Self.normalized(word)
        guard !key.isEmpty else { return self }
        var copy = self
        copy.blocked.removeAll { $0 == key }
        if !copy.yourWords.contains(where: { Self.normalized($0) == key }) {
            copy.yourWords.append(Self.singleSpaced(word))
        }
        return copy
    }

    public func removingYourWord(_ word: String) -> Lexicon {
        let key = Self.normalized(word)
        var copy = self
        copy.yourWords.removeAll { Self.normalized($0) == key }
        return copy
    }

    /// Learned words with their misheard forms as aliases, then the owner's words. One term per written form.
    public var hintTerms: [HintTerm] {
        var seen: Set<String> = []
        var terms: [HintTerm] = []
        for entry in learnedWords where seen.insert(Self.normalized(entry.written)).inserted {
            terms.append(HintTerm(text: entry.written, aliases: entry.heardForms))
        }
        for word in yourWords where seen.insert(Self.normalized(word)).inserted {
            terms.append(HintTerm(text: word))
        }
        return terms
    }

    /// Lowercased and single-spaced.
    private static func normalized(_ phrase: String) -> String {
        singleSpaced(phrase).lowercased()
    }

    private static func singleSpaced(_ phrase: String) -> String {
        phrase.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

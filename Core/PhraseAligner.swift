import Foundation

/// A phrase the speech model heard one way and the owner meant another.
public struct Substitution: Codable, Equatable, Hashable, Sendable {
    /// Lowercased and punctuation-free.
    public var heard: String
    public var written: String

    public init(heard: String, written: String) {
        self.heard = heard
        self.written = written
    }
}

/// Finds the phrases one transcript substituted for another, by aligning their words.
public enum PhraseAligner {
    /// `normalize` maps each lowercased, punctuation-free word before comparing, such as a spelling variety.
    /// Returns nothing for transcripts too long to align (see `WordAlignment.maxCells`).
    public static func substitutions(from hypothesis: String, to reference: String, maxWords: Int = 4,
                                     normalize: (String) -> String = { $0 }) -> [Substitution] {
        let heard = AlignedWord.words(in: hypothesis, normalize: normalize)
        let written = AlignedWord.words(in: reference, normalize: normalize)
        guard let alignment = WordAlignment(heard.map(\.key), written.map(\.key), freeEnds: false) else { return [] }
        return alignment.runs.compactMap { run in
            guard !run.heard.isEmpty, !run.written.isEmpty else { return nil }
            let span = run.withContext(written: written, heardLimit: heard.count, writtenLimit: 0..<written.count)
            guard span.heard.count <= maxWords, span.written.count <= maxWords else { return nil }
            return span.substitution(heard: heard, written: written, core: run.written)
        }
    }
}

/// One word of a transcript: as written, and as compared.
struct AlignedWord {
    /// The word without surrounding punctuation, in its original case.
    let display: String
    /// Lowercased and punctuation-free.
    let plain: String
    /// `plain` after the caller's normalisation.
    let key: String

    static func words(in text: String, normalize: (String) -> String = { $0 }) -> [AlignedWord] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let plain = String(token.lowercased().filter { $0.isLetter || $0.isNumber })
            guard !plain.isEmpty,
                  let start = token.firstIndex(where: isWordCharacter),
                  let end = token.lastIndex(where: isWordCharacter) else { return nil }
            return AlignedWord(display: String(token[start...end]), plain: plain, key: normalize(plain))
        }
    }

    /// Context words read mid-phrase, so they lose a sentence capital but keep "I" and acronyms such as "NASA".
    var asContext: String {
        if display == "I" || display.hasPrefix("I'") || display.hasPrefix("I’") { return display }
        let letters = display.filter(\.isLetter)
        if letters.count > 1, letters.allSatisfy(\.isUppercase) { return display }
        return display.lowercased()
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

/// A run of differing words: indices into the heard and written word lists.
struct AlignedSpan {
    var heard: Range<Int>
    var written: Range<Int>

    /// A written side of one short word, such as "G", takes the neighbouring matched word on both sides,
    /// so it reads as a phrase. `writtenLimit` is the stretch of written words aligned with the heard ones.
    func withContext(written words: [AlignedWord], heardLimit: Int, writtenLimit: Range<Int>) -> AlignedSpan {
        guard written.count == 1, words[written.lowerBound].plain.count < 3 else { return self }
        if heard.lowerBound > 0, written.lowerBound > writtenLimit.lowerBound {
            return AlignedSpan(heard: heard.lowerBound - 1..<heard.upperBound,
                               written: written.lowerBound - 1..<written.upperBound)
        }
        if heard.upperBound < heardLimit, written.upperBound < writtenLimit.upperBound {
            return AlignedSpan(heard: heard.lowerBound..<heard.upperBound + 1,
                               written: written.lowerBound..<written.upperBound + 1)
        }
        return self
    }

    /// Words inside `core` keep their case; context words around it are lowercased.
    func substitution(heard heardWords: [AlignedWord], written writtenWords: [AlignedWord],
                      core: Range<Int>) -> Substitution {
        Substitution(
            heard: heard.map { heardWords[$0].plain }.joined(separator: " "),
            written: written.map { core.contains($0) ? writtenWords[$0].display : writtenWords[$0].asContext }
                .joined(separator: " ")
        )
    }
}

/// Word-level Levenshtein alignment. Among equally short edit scripts it keeps the most matched words.
struct WordAlignment {
    /// Caps the step table at about 4 MB (one byte a cell), and the work at a few tens of milliseconds.
    static let maxCells = 4_000_000

    /// Maximal runs of unmatched words, in order. Either side of a run may be empty.
    private(set) var runs: [AlignedSpan] = []
    /// The written words the heard words were aligned against.
    private(set) var region: Range<Int> = 0..<0
    private(set) var matches = 0

    private enum Step: UInt8 { case match, substitute, dropHeard, addWritten }
    private struct Score { var cost: Int; var matches: Int }

    /// With `freeEnds`, written words before and after the aligned region cost nothing, which finds the
    /// heard words inside a longer written text. Nil when the two lists would need more than `maxCells`.
    init?(_ heard: [String], _ written: [String], freeEnds: Bool) {
        let rows = heard.count, width = written.count + 1
        guard (rows + 1) * width <= Self.maxCells else { return nil }
        // Scores are kept one row at a time; the steps are kept for the whole table to trace back.
        var steps = [Step?](repeating: nil, count: (rows + 1) * width)
        var previous = (0..<width).map { Score(cost: freeEnds ? 0 : $0, matches: 0) }
        for j in 1..<width where !freeEnds { steps[j] = .addWritten }
        for i in 1..<rows + 1 {
            var current = previous
            current[0] = Score(cost: i, matches: 0)
            steps[i * width] = .dropHeard
            for j in 1..<width {
                let same = heard[i - 1] == written[j - 1]
                var best = Score(cost: previous[j - 1].cost + (same ? 0 : 1),
                                 matches: previous[j - 1].matches + (same ? 1 : 0))
                var step = same ? Step.match : .substitute
                let up = Score(cost: previous[j].cost + 1, matches: previous[j].matches)
                if Self.better(up, than: best) { best = up; step = .dropHeard }
                let left = Score(cost: current[j - 1].cost + 1, matches: current[j - 1].matches)
                if Self.better(left, than: best) { best = left; step = .addWritten }
                current[j] = best
                steps[i * width + j] = step
            }
            previous = current
        }

        var end = width - 1
        if freeEnds {
            end = 0
            for j in 0..<width where Self.better(previous[j], than: previous[end]) { end = j }
        }
        matches = previous[end].matches

        var path: [Step] = []
        var i = rows, j = end
        while let step = steps[i * width + j] {
            path.append(step)
            switch step {
            case .match, .substitute: i -= 1; j -= 1
            case .dropHeard: i -= 1
            case .addWritten: j -= 1
            }
        }
        path.reverse()
        region = j..<end

        var open: AlignedSpan?
        for step in path {
            if step == .match {
                if let run = open { runs.append(run) }
                open = nil
                i += 1; j += 1
                continue
            }
            var run = open ?? AlignedSpan(heard: i..<i, written: j..<j)
            if step != .addWritten { i += 1 }
            if step != .dropHeard { j += 1 }
            run.heard = run.heard.lowerBound..<i
            run.written = run.written.lowerBound..<j
            open = run
        }
        if let run = open { runs.append(run) }
    }

    private static func better(_ a: Score, than b: Score) -> Bool {
        a.cost < b.cost || (a.cost == b.cost && a.matches > b.matches)
    }
}

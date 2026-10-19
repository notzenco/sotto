import Foundation

/// Spots the owner correcting a mishearing in text Sotto typed.
public enum FixDetector {
    private static let maxWords = 4

    /// `inserted` is what Sotto typed and `fieldText` the field's whole text read back later.
    /// Returns the one changed span when the rest of the typed text is intact and the change sounds alike.
    public static func fix(inserted: String, fieldText: String) -> Substitution? {
        let typed = AlignedWord.words(in: inserted)
        let field = AlignedWord.words(in: fieldText)
        let alignment = WordAlignment(typed.map(\.key), field.map(\.key), freeEnds: true)
        // At least one typed word must still be there to anchor the change, and only one span may differ.
        guard alignment.matches > 0, alignment.runs.count == 1, let run = alignment.runs.first,
              !run.heard.isEmpty, run.heard.count <= maxWords else { return nil }

        // A change at either end of the typed text can run into the field's neighbouring words, which the
        // alignment leaves outside the region ("Margie" → "my G" may align as "Margie" → "my").
        // Take the fewest of them that make the two sides sound alike.
        let before = run.heard.lowerBound == 0 ? min(run.written.lowerBound, maxWords) : 0
        let after = run.heard.upperBound == typed.count ? min(field.count - run.written.upperBound, maxWords) : 0
        let heard = run.heard.map { typed[$0].plain }.joined(separator: " ")
        for extra in 0...(before + after) {
            for back in max(0, extra - after)...min(extra, before) {
                let written = run.written.lowerBound - back..<run.written.upperBound + extra - back
                guard !written.isEmpty, written.count <= maxWords else { continue }
                let phrase = written.map { field[$0].plain }.joined(separator: " ")
                guard SoundAlike.similar(heard, phrase) else { continue }
                let core = AlignedSpan(heard: run.heard, written: written)
                let region = min(alignment.region.lowerBound, written.lowerBound)
                    ..< max(alignment.region.upperBound, written.upperBound)
                let span = core.withContext(written: field, heardLimit: typed.count, writtenLimit: region)
                guard span.heard.count <= maxWords, span.written.count <= maxWords else { return nil }
                return span.substitution(heard: typed, written: field, core: written)
            }
        }
        return nil
    }
}

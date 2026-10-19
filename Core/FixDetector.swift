import Foundation

/// Spots the owner correcting a mishearing in text Sotto typed.
public enum FixDetector {
    private static let maxWords = 4
    /// UTF-16 units read either side of the insertion: room for text the owner typed earlier in the field
    /// after Sotto inserted, and for the fix itself changing the text's length.
    private static let windowPad = 300

    /// `inserted` is what Sotto typed and `fieldText` the field's whole text read back later. `offset` is the
    /// UTF-16 offset in the field where the insertion started; when known, only the text around it is read.
    /// Returns the one changed span when the rest of the typed text is intact and the change sounds alike.
    public static func fix(inserted: String, fieldText: String, near offset: Int? = nil) -> Substitution? {
        let typed = AlignedWord.words(in: inserted)
        let text = offset.map { window(of: fieldText, from: $0, length: (inserted as NSString).length) } ?? fieldText
        let field = AlignedWord.words(in: text)
        guard let alignment = WordAlignment(typed.map(\.key), field.map(\.key), freeEnds: true) else { return nil }
        // The unchanged typed words anchor the change. Without an offset, half of them must still be there,
        // so a deleted insertion isn't matched against similar text elsewhere in the field.
        let anchors = offset == nil ? (typed.count + 1) / 2 : 1
        guard alignment.matches >= max(anchors, 1), alignment.runs.count == 1, let run = alignment.runs.first,
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

    /// The field's text from `windowPad` before the insertion to `windowPad` after its typed length,
    /// without the word fragments a cut leaves at either edge.
    private static func window(of fieldText: String, from offset: Int, length: Int) -> String {
        let text = fieldText as NSString
        let start = max(0, min(offset, text.length) - windowPad)
        let end = min(text.length, max(offset, 0) + length + windowPad)
        guard start < end else { return "" }
        let range = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        var slice = Substring(text.substring(with: range))
        if range.location > 0, !isSpace(text, at: range.location - 1) {
            slice = slice.drop { !$0.isWhitespace }
        }
        if NSMaxRange(range) < text.length, !isSpace(text, at: NSMaxRange(range)) {
            slice = slice.lastIndex(where: \.isWhitespace).map { slice[..<$0] } ?? ""
        }
        return String(slice)
    }

    private static func isSpace(_ text: NSString, at index: Int) -> Bool {
        let character = text.substring(with: text.rangeOfComposedCharacterSequence(at: index))
        return character.first?.isWhitespace ?? false
    }
}

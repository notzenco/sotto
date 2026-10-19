import XCTest
import SottoCore

final class LearningTests: XCTestCase {
    func testAlignerFindsTheMishearing() {
        XCTAssertEqual(PhraseAligner.substitutions(from: "What's up, Madgie?", to: "What's up, my G?"),
                       [Substitution(heard: "madgie", written: "my G")])
    }

    func testShortWrittenWordGetsContext() {
        XCTAssertEqual(PhraseAligner.substitutions(from: "My gee.", to: "My G."), [Substitution(heard: "my gee", written: "my G")])
    }

    func testAlignerIgnoresCasePunctuationAndNormalisedSpelling() {
        XCTAssertEqual(PhraseAligner.substitutions(from: "the colour", to: "The color.", normalize: { $0 == "colour" ? "color" : $0 }), [])
    }

    func testLongRewritesAndPureInsertionsAreIgnored() {
        XCTAssertEqual(PhraseAligner.substitutions(from: "a b c d e f g", to: "one two three four five six seven"), [])
        XCTAssertEqual(PhraseAligner.substitutions(from: "send it", to: "send it now"), [])
    }

    func testSoundAlike() {
        XCTAssertTrue(SoundAlike.similar("margie", "my g")); XCTAssertTrue(SoundAlike.similar("madgie", "my g"))
        XCTAssertTrue(SoundAlike.similar("gee", "g"))
        XCTAssertFalse(SoundAlike.similar("great", "awesome")); XCTAssertFalse(SoundAlike.similar("tuesday", "wednesday"))
    }

    func testFixDetector() {
        XCTAssertEqual(FixDetector.fix(inserted: " What's up, Margie?", fieldText: "hey mate. What's up, my G? see ya"),
                       Substitution(heard: "margie", written: "my G"))
        XCTAssertNil(FixDetector.fix(inserted: "That was great.", fieldText: "That was awesome."))
        XCTAssertNil(FixDetector.fix(inserted: "What's up, Margie?", fieldText: "What's up, Margie?"))
        XCTAssertNil(FixDetector.fix(inserted: "send it to Margie now", fieldText: ""))
        XCTAssertNil(FixDetector.fix(inserted: "call Margie and Madgie", fieldText: "call my G and my G"))
    }

    func testLexiconThresholdsAndBlocking() {
        let pair = Substitution(heard: "madgie", written: "my G")
        var lex = Lexicon()
        let clip1 = UUID(), clip2 = UUID()
        lex = lex.recording(pair, source: .teacher, clipID: clip1)
        XCTAssertTrue(lex.learnedWords.isEmpty)
        lex = lex.recording(pair, source: .teacher, clipID: clip1)
        XCTAssertTrue(lex.learnedWords.isEmpty)                      // same clip twice doesn't count
        lex = lex.recording(pair, source: .teacher, clipID: clip2)
        XCTAssertEqual(lex.learnedWords.map(\.written), ["my G"])
        XCTAssertEqual(lex.hintTerms, [HintTerm(text: "my G", aliases: ["madgie"])])
        lex = lex.deleting(id: lex.learnedWords[0].id)
        lex = lex.recording(Substitution(heard: "margie", written: "my G"), source: .fix, clipID: nil)
        XCTAssertTrue(lex.learnedWords.isEmpty)                      // blocked
        lex = lex.recording(pair, source: .compare, clipID: nil)
        XCTAssertEqual(lex.learnedWords.map(\.written), ["my G"])  // compare unblocks
    }

    func testFixLearnsAtOnceAndYourWordsUnblock() {
        var lex = Lexicon().recording(Substitution(heard: "margie", written: "my G"), source: .fix, clipID: nil)
        XCTAssertEqual(lex.learnedWords.count, 1)
        lex = lex.deleting(id: lex.learnedWords[0].id).addingYourWord("my G")
        XCTAssertTrue(lex.blocked.isEmpty)
        XCTAssertEqual(lex.hintTerms.map(\.text), ["my G"])
    }
}

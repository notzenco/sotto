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

    func testOrdinaryEditsDontSoundAlike() {
        for (a, b) in [("good", "great"), ("walk", "walked"), ("cat", "cats"), ("in", "on"), ("this", "these"),
                       ("like", "liked"), ("at", "it"), ("is", "as"), ("bad", "bed"), ("big", "bag")] {
            XCTAssertFalse(SoundAlike.similar(a, b), "\(a) / \(b)")
        }
    }

    func testRewordingInflectionAndRelocationAreNotFixes() {
        XCTAssertNil(FixDetector.fix(inserted: "Sounds good to me.", fieldText: "Sounds great to me."))
        XCTAssertNil(FixDetector.fix(inserted: "I walk there", fieldText: "I walked there"))
        XCTAssertNil(FixDetector.fix(inserted: "feed the cat now", fieldText: "feed the cats now"))
        XCTAssertNil(FixDetector.fix(inserted: "put it in there", fieldText: "put it on there"))
        XCTAssertNil(FixDetector.fix(inserted: "hi Gee", fieldText: "Notes from the meeting. hi Jo, thanks for coming."))
        XCTAssertNil(FixDetector.fix(inserted: "Margie", fieldText: "my G"))  // nothing left to anchor it
    }

    func testFixNearTheInsertionPoint() {
        let filler = String(repeating: "and then we talked about the weather for a while ", count: 8)
        let field = "What's up, Margie? " + filler + "What's up, my G?"
        let offset = (field as NSString).range(of: "What's up, my G?").location
        XCTAssertNil(FixDetector.fix(inserted: "What's up, Margie?", fieldText: field))  // found unchanged earlier
        XCTAssertEqual(FixDetector.fix(inserted: "What's up, Margie?", fieldText: field, near: offset),
                       Substitution(heard: "margie", written: "my G"))
        XCTAssertNil(FixDetector.fix(inserted: "What's up, Margie?", fieldText: field, near: 0))
    }

    func testEveryReportedMishearingOfMyGSoundsAlike() {
        for heard in ["maggie", "margie", "madgie"] {
            XCTAssertTrue(SoundAlike.similar(heard, "my g"), heard)
        }
        XCTAssertEqual(FixDetector.fix(inserted: "What's up, Maggie?", fieldText: "What's up, my G?"),
                       Substitution(heard: "maggie", written: "my G"))
    }

    func testFixDetectorAddsContextToAShortWord() {
        XCTAssertEqual(FixDetector.fix(inserted: "My gee. Later", fieldText: "My G. Later"),
                       Substitution(heard: "my gee", written: "my G"))
    }

    func testWordCapCountsTheContextWord() {
        XCTAssertEqual(PhraseAligner.substitutions(from: "ok one two three", to: "ok G"),
                       [Substitution(heard: "ok one two three", written: "ok G")])
        XCTAssertEqual(PhraseAligner.substitutions(from: "ok one two three four", to: "ok G"), [])
    }

    func testContextKeepsAcronymsAndLowercasesASingleCapital() {
        XCTAssertEqual(PhraseAligner.substitutions(from: "tell NASA gee", to: "tell NASA G"),
                       [Substitution(heard: "nasa gee", written: "NASA G")])
        XCTAssertEqual(PhraseAligner.substitutions(from: "A gee", to: "A G"), [Substitution(heard: "a gee", written: "a G")])
    }

    func testTeacherCountsTheSamePairOnTwoClips() {
        let clip1 = UUID(), clip2 = UUID()
        var lex = Lexicon()
            .recording(Substitution(heard: "madgie", written: "my G"), source: .teacher, clipID: clip1)
            .recording(Substitution(heard: "margie", written: "my G"), source: .teacher, clipID: clip2)
        XCTAssertTrue(lex.learnedWords.isEmpty)                      // different heard forms
        lex = lex.recording(Substitution(heard: "Margie", written: "My  G"), source: .teacher, clipID: clip1)
        XCTAssertEqual(lex.learnedWords.map(\.heardForms), [["madgie", "margie"]])
    }

    func testTeacherWithoutAClipNeverLearns() {
        let pair = Substitution(heard: "madgie", written: "my G")
        let lex = Lexicon().recording(pair, source: .teacher, clipID: nil).recording(pair, source: .teacher, clipID: nil)
        XCTAssertTrue(lex.learnedWords.isEmpty)
        XCTAssertEqual(lex.entries.count, 1)
    }

    func testRemovingYourWord() {
        let lex = Lexicon().addingYourWord("Sotto").addingYourWord("my G").removingYourWord("MY  g")
        XCTAssertEqual(lex.yourWords, ["Sotto"])
    }

    func testHintTermsListEachWrittenFormOnce() {
        let lex = Lexicon()
            .recording(Substitution(heard: "margie", written: "my G"), source: .fix, clipID: nil)
            .addingYourWord("My G").addingYourWord("Sotto")
        XCTAssertEqual(lex.hintTerms, [HintTerm(text: "my G", aliases: ["margie"]), HintTerm(text: "Sotto")])
    }

    func testContextualHintsPutYourWordsFirstThenNewestLearned() {
        let lex = Lexicon()
            .recording(Substitution(heard: "margie", written: "my G"), source: .fix, clipID: nil)
            .recording(Substitution(heard: "soto", written: "Sotto"), source: .fix, clipID: nil)
            .recording(Substitution(heard: "zenko", written: "Zenco"), source: .teacher, clipID: nil)
            .addingYourWord("Kian").addingYourWord("sotto")
        XCTAssertEqual(lex.contextualHints().map(\.text), ["Kian", "sotto", "my G"])
    }

    func testContextualHintsAreCapped() {
        var lex = Lexicon()
        for index in 0..<80 {
            lex = lex.recording(Substitution(heard: "heard\(index)", written: "learned\(index)"), source: .fix, clipID: nil)
        }
        for index in 0..<30 { lex = lex.addingYourWord("mine\(index)") }
        let hints = lex.contextualHints().map(\.text)
        XCTAssertEqual(hints.count, 100)
        XCTAssertEqual(Array(hints.prefix(31)), (0..<30).map { "mine\($0)" } + ["learned79"])
        XCTAssertEqual(hints.last, "learned10")
        XCTAssertEqual(lex.contextualHints(limit: 2).map(\.text), ["mine0", "mine1"])
    }

    func testOlderLexiconFilesDecodeWithDefaults() throws {
        let id = UUID()
        let word = """
        {"id": "\(id.uuidString)", "written": "my G", "heardForms": ["margie"], "sources": ["fix"], "count": 1, "learned": true}
        """
        let decoded = try JSONDecoder().decode(LearnedWord.self, from: Data(word.utf8))
        XCTAssertEqual(decoded, LearnedWord(id: id, written: "my G", heardForms: ["margie"], sources: [.fix],
                                            count: 1, learned: true))

        let lexicon = try JSONDecoder().decode(Lexicon.self, from: Data(#"{"entries": [\#(word)]}"#.utf8))
        XCTAssertEqual(lexicon, Lexicon(entries: [decoded]))
    }

    func testUnreadableLexiconEntriesAreDroppedAlone() throws {
        let json = """
        {"entries": [
          {"written": "my G", "heardForms": ["margie"], "sources": ["fix"], "count": 1, "learned": true},
          {"written": "Sotto", "sources": ["telepathy"]},
          {"heardForms": ["no written form"]}
        ], "yourWords": ["Sotto"]}
        """
        let lexicon = try JSONDecoder().decode(Lexicon.self, from: Data(json.utf8))
        XCTAssertEqual(lexicon.entries.map(\.written), ["my G"])
        XCTAssertEqual(lexicon.yourWords, ["Sotto"])
    }
}

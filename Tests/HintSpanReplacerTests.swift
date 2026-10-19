import XCTest
import SottoCore

final class HintSpanReplacerTests: XCTestCase {
    func testTrailingPunctuationStays() {
        XCTAssertEqual(
            HintSpanReplacer.apply([.init(original: "Madgie.", replacement: "my G")], to: "Thanks, Madgie."),
            "Thanks, my G.")
    }

    func testPunctuationAfterAnOpeningSpanStays() {
        XCTAssertEqual(
            HintSpanReplacer.apply([.init(original: "Madgie,", replacement: "my G")], to: "Madgie, how are you?"),
            "my G, how are you?")
    }

    func testTwoWordSpanKeepsTrailingQuestionMark() {
        XCTAssertEqual(
            HintSpanReplacer.apply([.init(original: "my gee?", replacement: "my G")], to: "What's up, my gee?"),
            "What's up, my G?")
    }

    func testLeadingQuoteAndTrailingPunctuationStay() {
        XCTAssertEqual(
            HintSpanReplacer.apply([.init(original: "\"Madgie!\"", replacement: "my G")], to: "He said \"Madgie!\" twice"),
            "He said \"my G!\" twice")
    }

    func testSpanNotFoundGivesNil() {
        XCTAssertNil(HintSpanReplacer.apply([.init(original: "Madgie", replacement: "my G")], to: "Thanks, Maggie."))
    }

    func testSpanMustBeWholeWords() {
        XCTAssertNil(HintSpanReplacer.apply([.init(original: "adgie", replacement: "my G")], to: "Madgie is here"))
    }

    func testReplacementCaseIsKept() {
        XCTAssertEqual(
            HintSpanReplacer.apply([.init(original: "sotto", replacement: "Sotto")], to: "open sotto now"),
            "open Sotto now")
    }

    func testSeveralSpansInAnyOrderLeaveTheRestUntouched() {
        let text = "Madgie,  ask Kwame-ish about it. Madgie?"
        let result = HintSpanReplacer.apply(
            [
                .init(original: "Madgie?", replacement: "my G"),
                .init(original: "Madgie,", replacement: "my G"),
            ],
            to: text)
        XCTAssertEqual(result, "my G,  ask Kwame-ish about it. my G?")
    }

    func testRepeatedSpanReplacesSuccessiveOccurrences() {
        XCTAssertEqual(
            HintSpanReplacer.apply(
                [.init(original: "Madgie", replacement: "my G"), .init(original: "Madgie", replacement: "my G")],
                to: "Madgie and Madgie"),
            "my G and my G")
    }
}

import XCTest
@testable import SottoCore

final class InsertJoinTests: XCTestCase {
    func testSpaceAfterTheEndOfASentence() {
        XCTAssertEqual(
            InsertJoin.fit("Yeah, we can start.", before: "It seems to be working well.", mode: .prose),
            " Yeah, we can start."
        )
    }

    func testStartOfAFieldIsLeftAlone() {
        XCTAssertEqual(InsertJoin.fit("Hello.", before: "", mode: .prose), "Hello.")
    }

    func testUnknownContextIsLeftAlone() {
        XCTAssertEqual(InsertJoin.fit("And then.", before: nil, mode: .prose), "And then.")
    }

    func testNoSpaceAfterWhitespace() {
        XCTAssertEqual(InsertJoin.fit("There.", before: "Hi. ", mode: .prose), "There.")
        XCTAssertEqual(InsertJoin.fit("There.", before: "Hi.\t", mode: .prose), "There.")
    }

    func testNewLineStartsASentence() {
        XCTAssertEqual(InsertJoin.fit("World.", before: "hello\n", mode: .prose), "World.")
    }

    func testNoSpaceAfterOpeningSymbols() {
        for before in ["see (", "list [", "{", "path/", "a\\", "@", "#", "snake_", "re-", "$", "“", "‘"] {
            XCTAssertEqual(InsertJoin.fit("value", before: before, mode: .literal), "value", before)
        }
    }

    func testSpacedDashIsPunctuationNotAHyphen() {
        XCTAssertEqual(InsertJoin.fit("Next.", before: "wait -", mode: .prose), " Next.")
    }

    func testStraightQuoteOpensAfterSpaceAndClosesAfterText() {
        XCTAssertEqual(InsertJoin.fit("Hello", before: "He said \"", mode: .prose), "Hello")
        XCTAssertEqual(InsertJoin.fit("Hello", before: "'", mode: .prose), "Hello")
        XCTAssertEqual(InsertJoin.fit("Next.", before: "He said \"done.\"", mode: .prose), " Next.")
        XCTAssertEqual(InsertJoin.fit("Next.", before: "the dogs'", mode: .prose), " Next.")
    }

    func testNoSpaceBeforeLeadingPunctuation() {
        XCTAssertEqual(InsertJoin.fit(", and then", before: "Hello", mode: .prose), ", and then")
        XCTAssertEqual(InsertJoin.fit("?", before: "Really", mode: .prose), "?")
    }

    func testFirstWordIsLowercasedMidSentence() {
        XCTAssertEqual(
            InsertJoin.fit("And then I left.", before: "I went to the shop", mode: .prose),
            " and then I left."
        )
        XCTAssertEqual(InsertJoin.fit("Maybe tomorrow.", before: "Well,", mode: .prose), " maybe tomorrow.")
        XCTAssertEqual(InsertJoin.fit("Or not.", before: "Yes;", mode: .prose), " or not.")
        XCTAssertEqual(InsertJoin.fit("Minutes.", before: "about 5", mode: .prose), " minutes.")
        XCTAssertEqual(InsertJoin.fit("And then.", before: "the shop ", mode: .prose), "and then.")
        XCTAssertEqual(InsertJoin.fit(", And then", before: "Hello", mode: .prose), ", and then")
    }

    func testCapitalIsKeptWhereASentenceMayStart() {
        XCTAssertEqual(InsertJoin.fit("Next one.", before: "Done.", mode: .prose), " Next one.")
        XCTAssertEqual(InsertJoin.fit("Really?", before: "What!", mode: .prose), " Really?")
        XCTAssertEqual(InsertJoin.fit("Apples.", before: "Shopping:", mode: .prose), " Apples.")
        XCTAssertEqual(InsertJoin.fit("Okay.", before: "Wait…", mode: .prose), " Okay.")
    }

    func testIAndAcronymsKeepTheirCapitals() {
        XCTAssertEqual(InsertJoin.fit("I'm going.", before: "and then", mode: .prose), " I'm going.")
        XCTAssertEqual(InsertJoin.fit("I’ll go.", before: "so", mode: .prose), " I’ll go.")
        XCTAssertEqual(InsertJoin.fit("I think.", before: "so", mode: .prose), " I think.")
        XCTAssertEqual(InsertJoin.fit("NASA data.", before: "we use", mode: .prose), " NASA data.")
        XCTAssertEqual(InsertJoin.fit("OK then.", before: "fine", mode: .prose), " OK then.")
    }

    func testProtectedWordsKeepTheirCapitals() {
        let text = InsertJoin.fit("Sydney today.", before: "we flew to", mode: .prose) { $0 == "Sydney" }
        XCTAssertEqual(text, " Sydney today.")
    }

    func testOnlyTheFirstWordIsConsidered() {
        let text = InsertJoin.fit("Then Sydney.", before: "and", mode: .prose) { $0 == "Then" }
        XCTAssertEqual(text, " Then Sydney.")
        XCTAssertEqual(InsertJoin.fit("5 Things.", before: "the top", mode: .prose), " 5 Things.")
    }

    func testLiteralModeSpacesButNeverChangesCase() {
        XCTAssertEqual(InsertJoin.fit("Status", before: "git", mode: .literal), " Status")
        XCTAssertEqual(InsertJoin.fit("Then run it.", before: "Fix the bug.", mode: .literal), " Then run it.")
    }

    func testTextThatAlreadyStartsWithWhitespaceGetsNoExtraSpace() {
        XCTAssertEqual(InsertJoin.fit(" there", before: "Hi", mode: .literal), " there")
    }
}

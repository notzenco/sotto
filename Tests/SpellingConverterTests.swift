import XCTest
import SottoCore

final class SpellingConverterTests: XCTestCase {
    func testAustralianRespellsOrdinaryWords() {
        XCTAssertEqual(SpellingConverter.convert("make the button color darker", to: .australian), "make the button colour darker")
        XCTAssertEqual(SpellingConverter.convert("I realize the center is gray", to: .british), "I realise the centre is grey")
    }

    func testCaseIsPreserved() {
        XCTAssertEqual(SpellingConverter.convert("Color me surprised", to: .australian), "Colour me surprised")
    }

    func testCodeLookingWordsAreSkipped() {
        let text = "use `color` and fooColor and font_color and file.color, see https://example.com/color or ./color/x"
        XCTAssertEqual(SpellingConverter.convert(text, to: .australian), text)
        XCTAssertEqual(SpellingConverter.convert("set COLOR now", to: .australian), "set COLOR now")
    }

    func testAmericanGoesTheOtherWay() {
        XCTAssertEqual(SpellingConverter.convert("the colour of the centre", to: .american), "the color of the center")
    }

    func testAustralianKeepsProgram() {
        XCTAssertEqual(SpellingConverter.convert("a TV program", to: .australian), "a TV program")
        XCTAssertEqual(SpellingConverter.convert("a TV program", to: .british), "a TV programme")
    }

    func testSwearingIsUntouched() {
        XCTAssertEqual(SpellingConverter.convert("fucking shit, the color", to: .australian), "fucking shit, the colour")
        XCTAssertEqual(TranscriptFormatter.format("fuck this shit", mode: .prose), "Fuck this shit.")
        XCTAssertEqual(Rulebook().remember(heard: "john", written: "Jon").applying(to: "fuck off john"), "fuck off Jon")
    }

    func testPunctuationAroundWordsSurvives() {
        XCTAssertEqual(SpellingConverter.convert("Color, flavor; honor!", to: .australian), "Colour, flavour; honour!")
    }
}

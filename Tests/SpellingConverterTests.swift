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
        for variety in SpellingVariety.allCases {
            for text in ["what an asshole", "what an arsehole", "bloody hell", "bugger off", "piss off, you perv"] {
                XCTAssertEqual(SpellingConverter.convert(text, to: variety), text, "\(variety): \(text)")
            }
        }
    }

    func testMeaningChangingPairsAreLeftAlone() {
        XCTAssertEqual(SpellingConverter.convert("among the prized work, she learned", to: .australian), "among the prized work, she learned")
        XCTAssertEqual(SpellingConverter.convert("the prev page", to: .american), "the prev page")
    }

    func testCodeLikePrefixesAndDigitsAreSkipped() {
        let text = "set --color-primary and #color and $color and @color to color2"
        XCTAssertEqual(SpellingConverter.convert(text, to: .australian), text)
    }

    func testPunctuationAroundWordsSurvives() {
        XCTAssertEqual(SpellingConverter.convert("Color, flavor; honor!", to: .australian), "Colour, flavour; honour!")
    }

    /// About shows this notice, so it must stay word for word the licence in the word list's header.
    func testLicenceNoticeMatchesTheWordListHeader() throws {
        let table = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Core/SpellingTable.swift")
        let header = try String(contentsOf: table, encoding: .utf8)
            .components(separatedBy: "\n")
            .prefix { $0.hasPrefix("//") }
            .map { $0 == "//" ? "" : String($0.dropFirst(3)) }
        let start = try XCTUnwrap(header.firstIndex { $0.hasPrefix("Copyright 2000-2019") })
        XCTAssertEqual(SpellingConverter.licenceNotice, header[start...].joined(separator: "\n"))
        XCTAssertTrue(SpellingConverter.licenceNotice.hasSuffix("SUCH DAMAGE."))
    }
}

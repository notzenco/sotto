import XCTest
import SottoCore

final class SettingsTests: XCTestCase {
    func testColorConstructionClampsComponents() {
        let color = RGBColor(red: 2, green: -1, blue: 0.5)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0.5)
    }

    func testColorMutationClampsComponents() {
        var color = RGBColor.paper
        color.red = -1
        color.green = 2
        color.blue = -0.5
        XCTAssertEqual(color, RGBColor(red: 0, green: 1, blue: 0))
    }

    func testColorDecodingClampsComponents() throws {
        let json = #"{"red":2,"green":-1,"blue":0.5}"#
        let color = try JSONDecoder().decode(RGBColor.self, from: Data(json.utf8))
        XCTAssertEqual(color, RGBColor(red: 1, green: 0, blue: 0.5))
    }

    func testNonFiniteColorComponentsBecomeZero() throws {
        var color = RGBColor(red: .nan, green: .infinity, blue: -.infinity)
        XCTAssertEqual(color, RGBColor(red: 0, green: 0, blue: 0))
        color.red = .infinity
        color.green = -.infinity
        color.blue = .nan
        XCTAssertEqual(color, RGBColor(red: 0, green: 0, blue: 0))

        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        let json = #"{"red":"NaN","green":"Infinity","blue":"-Infinity"}"#
        XCTAssertEqual(try decoder.decode(RGBColor.self, from: Data(json.utf8)), color)
    }

    func testMalformedBarColorFallsBackAndKeepsOtherFields() throws {
        let json = #"{"style":"notch","position":"top","size":1.2,"barColor":"invalid","background":"light","showWords":true,"display":"main"}"#
        let settings = try JSONDecoder().decode(IndicatorSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.barColor, .paper)
        XCTAssertEqual(settings.style, .notch)
        XCTAssertEqual(settings.position, .top)
        XCTAssertEqual(settings.size, 1.2)
        XCTAssertEqual(settings.background, .light)
        XCTAssertTrue(settings.showWords)
        XCTAssertEqual(settings.display, .main)
    }

    func testDecodesTodaysSettingsFile() throws {
        let json = #"{"historyHours":24,"keepFirstSyllable":true,"dictationCount":13,"inputDeviceID":136,"modeOverride":"literal"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.historyHours, 24); XCTAssertEqual(s.dictationCount, 13)
        XCTAssertEqual(s.inputDeviceID, 136); XCTAssertEqual(s.modeOverride, .literal)
        XCTAssertEqual(s.indicator, IndicatorSettings())
    }

    func testEmptyObjectGivesDefaults() throws {
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)), AppSettings())
    }

    func testUnknownStyleFallsBackToPillAndKeepsOtherFields() throws {
        let json = #"{"historyHours":24,"indicator":{"style":"blob","showWords":true}}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.indicator.style, .pill); XCTAssertTrue(s.indicator.showWords); XCTAssertEqual(s.historyHours, 24)
    }

    func testSizeIsClampedOnDecode() throws {
        let json = #"{"indicator":{"size":9}}"#
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).indicator.size, 1.5)
    }

    func testRoundTrip() throws {
        var s = AppSettings(); s.indicator.style = .notch; s.indicator.barColor = .pink; s.indicator.size = 1.2
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)), s)
    }

    func testHexPresets() {
        XCTAssertEqual(RGBColor.paper.hex, "#F4EFE6")
        XCTAssertEqual(RGBColor.presets.map(\.hex), ["#F4EFE6", "#FFFFFF", "#5AC8FA", "#7EE0A1", "#FF7EB6", "#FFB340"])
        XCTAssertNil(RGBColor(hex: "nope"))
    }
}

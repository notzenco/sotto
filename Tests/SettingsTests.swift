import XCTest
import SottoCore

final class SettingsTests: XCTestCase {
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

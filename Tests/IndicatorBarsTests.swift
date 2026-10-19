import XCTest
@testable import SottoCore

final class IndicatorBarsTests: XCTestCase {
    func testRequestedBarCount() {
        XCTAssertEqual(IndicatorBars.heights(level: 0.7, count: 14, time: 0).count, 14)
        XCTAssertEqual(IndicatorBars.heights(level: 0.7, count: 0, time: 0), [])
        XCTAssertEqual(IndicatorBars.heights(level: 0.7, count: -1, time: 0), [])
    }

    func testSilenceKeepsEveryBarAtTheFloor() {
        XCTAssertEqual(IndicatorBars.floor, 0.14)
        XCTAssertEqual(IndicatorBars.heights(level: 0, count: 14, time: 0),
                       [Float](repeating: 0.14, count: 14))
    }

    func testMiddleBarsAreTallerThanTheEdges() {
        let heights = IndicatorBars.heights(level: 1, count: 14, time: 0)
        XCTAssertGreaterThan(heights[6], heights[0])
        XCTAssertGreaterThan(heights[7], heights[13])
    }

    func testHeightsStayWithinBoundsAtEveryLevel() {
        for level: Float in [-1, 0, 0.5, 1, 5] {
            for time in [0.0, 0.5, 2.0] {
                let heights = IndicatorBars.heights(level: level, count: 14, time: time)
                XCTAssertTrue(heights.allSatisfy { (0.14...1).contains($0) })
            }
        }
        XCTAssertEqual(IndicatorBars.heights(level: -1, count: 14, time: 0),
                       IndicatorBars.heights(level: 0, count: 14, time: 0))
        XCTAssertEqual(IndicatorBars.heights(level: 5, count: 14, time: 0),
                       IndicatorBars.heights(level: 1, count: 14, time: 0))
    }

    func testNonFiniteLevelsCountAsSilence() {
        for level: Float in [.nan, .infinity, -.infinity] {
            XCTAssertEqual(IndicatorBars.heights(level: level, count: 14, time: 0),
                           [Float](repeating: 0.14, count: 14))
        }
    }

    func testSingleBarUsesTheFullShapeAndTimeChangesItsHeight() {
        XCTAssertEqual(IndicatorBars.heights(level: 1, count: 1, time: 0)[0],
                       0.8, accuracy: 0.00001)
        XCTAssertEqual(IndicatorBars.heights(level: 1, count: 1, time: .pi / 14)[0],
                       1, accuracy: 0.00001)
    }
}

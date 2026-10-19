import XCTest
@testable import SottoCore

final class LevelMeterTests: XCTestCase {
    func testNormalizedMapsDecibelsOntoTheFloor() {
        XCTAssertEqual(LevelMeter.normalized(rms: 1, floorDecibels: -50), 1, accuracy: 0.001)
        XCTAssertEqual(LevelMeter.normalized(rms: 0.1, floorDecibels: -50), 0.6, accuracy: 0.001)
        XCTAssertEqual(LevelMeter.normalized(rms: 0, floorDecibels: -50), 0, accuracy: 0.001)
        XCTAssertEqual(LevelMeter.normalized(rms: 0.001, floorDecibels: -50), 0, accuracy: 0.001)
    }

    func testAttackIsFasterThanRelease() {
        let loud = [Float](repeating: 1, count: 512)
        let silence = [Float](repeating: 0, count: 512)
        var attackMeter = LevelMeter()
        XCTAssertEqual(attackMeter.ingest(loud), 0.6, accuracy: 0.001)

        var releaseMeter = LevelMeter()
        for _ in 0..<20 {
            _ = releaseMeter.ingest(loud)
        }
        XCTAssertGreaterThan(releaseMeter.level, 0.9999)
        XCTAssertEqual(releaseMeter.ingest(silence), 0.85, accuracy: 0.001)
    }

    func testNonFiniteSamplesAreIgnored() {
        var meter = LevelMeter()
        let invalid = meter.ingest([.nan, .infinity, -.infinity])
        XCTAssertEqual(invalid, 0, accuracy: 0.001)
        XCTAssertTrue(invalid.isFinite)
        let mixed = meter.ingest([.nan, 1, 1, .infinity])
        XCTAssertEqual(mixed, 0.6, accuracy: 0.001)
        XCTAssertTrue(mixed.isFinite)
        XCTAssertEqual(meter.ingest([.nan, .infinity, -.infinity]), mixed, accuracy: 0.001)
    }

    func testEmptyBufferLeavesLevelUnchanged() {
        var meter = LevelMeter()
        let previous = meter.ingest([1, 1])
        XCTAssertEqual(meter.ingest([]), previous, accuracy: 0.001)
    }

    func testResetReturnsToRest() {
        var meter = LevelMeter()
        _ = meter.ingest([1, 1])
        meter.reset()
        XCTAssertEqual(meter.level, 0, accuracy: 0.001)
        XCTAssertEqual(meter.ingest([1, 1]), 0.6, accuracy: 0.001)
    }
}

import XCTest
@testable import SottoCore

final class IndicatorTests: XCTestCase {
    func testProblemCopy() {
        XCTAssertEqual(TakeProblem.notHeard.message, "Didn't catch that")
        XCTAssertEqual(TakeProblem.passwordField.message, "Won't type into a password field")
        XCTAssertEqual(TakeProblem.focusMoved.message, "You moved away, so it's kept for Copy Last")
        XCTAssertEqual(TakeProblem.noTextField.message, "No text field, so it's kept for Copy Last")
        XCTAssertEqual(TakeProblem.couldNotType.message, "Couldn't type here, so it's kept for Copy Last")
        XCTAssertEqual(TakeProblem.accessibilityOff.message, "Turn on Accessibility for Sotto")
        XCTAssertEqual(TakeProblem.microphoneOff.message, "Turn on Microphone for Sotto")
        XCTAssertEqual(TakeProblem.modelDownloading.message, "Still downloading the speech model")
    }

    func testLinger() {
        XCTAssertEqual(IndicatorPhase.done.linger, 0.9)
        XCTAssertEqual(IndicatorPhase.problem(.notHeard).linger, 4)
        XCTAssertEqual(IndicatorPhase.cancelled.linger, 0)
        XCTAssertNil(IndicatorPhase.listening(handsFree: true).linger)
        XCTAssertNil(IndicatorPhase.working.linger)
    }

    func testCurrentExpiryHides() {
        var schedule = IndicatorSchedule()
        let generation = schedule.show(.problem(.notHeard))
        XCTAssertTrue(schedule.expire(generation))
        XCTAssertEqual(schedule.phase, .hidden)
    }

    func testStaleExpiryDoesNotHideNewTake() {
        var schedule = IndicatorSchedule()
        let old = schedule.show(.done)
        _ = schedule.show(.listening(handsFree: false))
        XCTAssertFalse(schedule.expire(old))
        XCTAssertEqual(schedule.phase, .listening(handsFree: false))
    }
}

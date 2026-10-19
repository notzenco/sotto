import XCTest
@testable import SottoCore

final class TakeLedgerTests: XCTestCase {
    func testAnyCommitCountsWhileASupersededTakeIsStillWorking() {
        var ledger = TakeLedger()
        XCTAssertFalse(ledger.isCommitting)
        let a = ledger.begin()
        XCTAssertFalse(ledger.isCommitting)
        _ = ledger.finish()
        _ = ledger.begin()
        XCTAssertFalse(ledger.isPending)
        XCTAssertTrue(ledger.isCommitting, "A still commits while B listens")
        ledger.complete(a)
        XCTAssertFalse(ledger.isCommitting)
    }

    func testOverlapKeepsOwnInsertionButCannotReadOrPresentTheNewTake() throws {
        var ledger = TakeLedger()
        let a = ledger.begin()
        XCTAssertEqual(ledger.finish(), a)
        let b = ledger.begin()
        XCTAssertFalse(ledger.isCurrent(a), "A must not read B's live session while B listens")
        XCTAssertTrue(ledger.allowsInsertion(a), "Supersession must preserve A's own result")
        XCTAssertEqual(ledger.finish(), b)
        XCTAssertFalse(ledger.isCurrent(a), "A must not read B's session after B releases either")
        XCTAssertFalse(ledger.canPresent(a))
        XCTAssertTrue(ledger.canPresent(b))
        ledger.complete(a)
        XCTAssertEqual(ledger.current, b)
        XCTAssertTrue(ledger.isPending)
    }

    func testEscapeDuringWorkingCancelsInsertionAndPresentation() {
        var ledger = TakeLedger()
        let take = ledger.begin()
        _ = ledger.finish()
        XCTAssertTrue(ledger.isPending)
        // HoldTracker has already released the key; Escape must use the ledger.
        var hold = HoldTracker()
        XCTAssertEqual(hold.escape(), .ignore)
        var phase = IndicatorPhase.working
        if ledger.cancel() != nil { phase = .cancelled }
        XCTAssertEqual(phase, .cancelled)
        XCTAssertFalse(ledger.isPending)
        XCTAssertFalse(ledger.allowsInsertion(take))
        XCTAssertFalse(ledger.isCurrent(take))
        XCTAssertFalse(ledger.canPresent(take))
        XCTAssertNil(ledger.cancel())
    }

    func testMicrophoneDeniedAttemptOwnsPresentation() {
        var ledger = TakeLedger()
        let a = ledger.begin()
        _ = ledger.finish()
        let denied = ledger.begin() // Ownership precedes permission validation.
        var phase = IndicatorPhase.problem(.microphoneOff)
        ledger.complete(denied)
        if ledger.canPresent(a) { phase = .done }
        XCTAssertEqual(phase, .problem(.microphoneOff))
        XCTAssertFalse(ledger.isCurrent(a))
        XCTAssertTrue(ledger.allowsInsertion(a))
        XCTAssertFalse(ledger.isPending)
    }

    func testSingleTakePresentsItsResultAndRetires() {
        var ledger = TakeLedger()
        let take = ledger.begin()
        XCTAssertTrue(ledger.isCurrent(take))
        XCTAssertFalse(ledger.isPending)
        XCTAssertFalse(ledger.allowsInsertion(take))
        XCTAssertEqual(ledger.finish(), take)
        XCTAssertTrue(ledger.isPending)
        XCTAssertTrue(ledger.allowsInsertion(take))
        XCTAssertTrue(ledger.canPresent(take))
        ledger.complete(take)
        XCTAssertFalse(ledger.isPending)
        XCTAssertFalse(ledger.allowsInsertion(take))
        XCTAssertFalse(ledger.canPresent(take))
        XCTAssertNil(ledger.current)
    }

    func testCancellingNewTakeDoesNotCancelSupersededPendingTake() {
        var ledger = TakeLedger()
        let a = ledger.begin()
        _ = ledger.finish()
        let b = ledger.begin()
        XCTAssertEqual(ledger.cancel(), b)
        XCTAssertTrue(ledger.allowsInsertion(a))
        XCTAssertFalse(ledger.canPresent(a))
        XCTAssertFalse(ledger.allowsInsertion(b))
        ledger.complete(a)
        XCTAssertFalse(ledger.allowsInsertion(a))
    }
}

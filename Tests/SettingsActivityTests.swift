import XCTest
@testable import SottoCore

final class SettingsActivityTests: XCTestCase {
    func testRetainedMicrophonePaneStopsOnCloseAndRestartsOnReopen() {
        var activity = SettingsActivity()
        activity.microphoneSelected = true
        XCTAssertFalse(activity.watchesMeter)
        activity.windowVisible = true
        XCTAssertTrue(activity.watchesMeter)
        // No pane disappearance: the selected Microphone content is retained.
        activity.windowVisible = false
        XCTAssertFalse(activity.watchesMeter)
        activity.windowVisible = true
        XCTAssertTrue(activity.watchesMeter)
    }

    func testMinimisingAndRestoringUsesTheSameVisibilityContract() {
        var activity = SettingsActivity()
        activity.windowVisible = true
        activity.microphoneSelected = true
        XCTAssertTrue(activity.watchesMeter)
        activity.windowVisible = false
        XCTAssertFalse(activity.watchesMeter)
        activity.windowVisible = true
        XCTAssertTrue(activity.watchesMeter)
    }

    func testPaneChangesWhileHiddenDoNotStartTheMeter() {
        var activity = SettingsActivity()
        activity.windowVisible = true
        activity.microphoneSelected = true
        XCTAssertTrue(activity.watchesMeter)
        activity.microphoneSelected = false
        XCTAssertFalse(activity.watchesMeter)
        activity.windowVisible = false
        activity.microphoneSelected = true
        XCTAssertFalse(activity.watchesMeter)
        activity.microphoneSelected = false
        activity.windowVisible = true
        XCTAssertFalse(activity.watchesMeter)
    }
}

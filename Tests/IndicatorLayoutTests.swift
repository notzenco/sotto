import XCTest
@testable import SottoCore

final class IndicatorLayoutTests: XCTestCase {
    private let s = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 60, width: 1512, height: 884),
        notch: CGRect(x: 656, y: 950, width: 200, height: 32)
    )
    private let pill = CGSize(width: 84, height: 24)

    private func place(
        body: CGSize? = nil, caption: CGSize? = nil,
        style: IndicatorStyle = .pill, position: IndicatorPosition = .bottom,
        caret: CGRect? = nil
    ) -> IndicatorPlacement {
        IndicatorLayout.place(body: body ?? pill, caption: caption, style: style,
                              position: position, screen: s, caret: caret)
    }

    func testBottom() {
        XCTAssertEqual(place().body, CGRect(x: 714, y: 76, width: 84, height: 24))
    }

    func testTop() {
        XCTAssertEqual(place(position: .top).body, CGRect(x: 714, y: 912, width: 84, height: 24))
    }

    func testNotchCentresOnTheNotch() {
        XCTAssertEqual(place(body: CGSize(width: 300, height: 32), style: .notch).body,
                       CGRect(x: 606, y: 950, width: 300, height: 32))
    }

    func testBelowTheCaret() {
        XCTAssertEqual(place(position: .caret, caret: CGRect(x: 400, y: 500, width: 2, height: 18)).body,
                       CGRect(x: 359, y: 468, width: 84, height: 24))
    }

    func testAboveTheCaretNearTheBottom() {
        XCTAssertEqual(place(position: .caret, caret: CGRect(x: 400, y: 70, width: 2, height: 18)).body,
                       CGRect(x: 359, y: 96, width: 84, height: 24))
    }

    func testCaretCaptionGoesAwayFromTheCaretAbove() throws {
        let result = place(caption: CGSize(width: 200, height: 18), position: .caret,
                           caret: CGRect(x: 400, y: 70, width: 2, height: 18))
        XCTAssertEqual(result.body, CGRect(x: 359, y: 96, width: 84, height: 24))
        let caption = try XCTUnwrap(result.caption)
        XCTAssertEqual(caption, CGRect(x: 301, y: 126, width: 200, height: 18))
        let band = CGRect(x: 0, y: 68, width: 1512, height: 22)
        XCTAssertFalse(result.body.union(caption).intersects(band))
    }

    func testCaretCaptionGoesAwayFromTheCaretBelow() {
        let result = place(caption: CGSize(width: 200, height: 18), position: .caret,
                           caret: CGRect(x: 400, y: 500, width: 2, height: 18))
        XCTAssertEqual(result.body, CGRect(x: 359, y: 468, width: 84, height: 24))
        XCTAssertEqual(result.caption, CGRect(x: 301, y: 444, width: 200, height: 18))
    }

    func testNarrowScreenClampsWidthsToAvailableSpace() throws {
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 320, height: 600),
                                    visibleFrame: CGRect(x: 0, y: 0, width: 320, height: 580),
                                    notch: nil)
        let result = IndicatorLayout.place(body: CGSize(width: 900, height: 24),
                                           caption: CGSize(width: 400, height: 18),
                                           style: .pill, position: .bottom, screen: screen, caret: nil)
        let caption = try XCTUnwrap(result.caption)
        XCTAssertEqual(result.body.width, 304)
        XCTAssertEqual(caption.width, 304)
        for rect in [result.body, caption] {
            XCTAssertGreaterThanOrEqual(rect.minX, screen.visibleFrame.minX)
            XCTAssertLessThanOrEqual(rect.maxX, screen.visibleFrame.maxX)
            XCTAssertGreaterThanOrEqual(rect.minY, screen.visibleFrame.minY)
            XCTAssertLessThanOrEqual(rect.maxY, screen.visibleFrame.maxY)
        }
    }

    func testTallCaptionStaysOnScreen() throws {
        let caption = try XCTUnwrap(place(caption: CGSize(width: 200, height: 900)).caption)
        XCTAssertEqual(caption, CGRect(x: 656, y: 82, width: 200, height: 900))
        XCTAssertGreaterThanOrEqual(caption.minY, s.frame.minY)
        XCTAssertLessThanOrEqual(caption.maxY, s.frame.maxY)
    }

    func testCaretPositionWithoutCaretFallsBackToBottom() {
        XCTAssertEqual(place(position: .caret).body, CGRect(x: 714, y: 76, width: 84, height: 24))
    }

    func testBottomFlipsToTopWhenItWouldCoverTheCaretLine() {
        XCTAssertEqual(place(caret: CGRect(x: 700, y: 80, width: 2, height: 16)).body,
                       CGRect(x: 714, y: 912, width: 84, height: 24))
    }

    func testCaptionAboveBottomPill() {
        XCTAssertEqual(place(caption: CGSize(width: 200, height: 18)).caption,
                       CGRect(x: 656, y: 106, width: 200, height: 18))
    }

    func testNotchCaptionDropsBelowTheCaretLine() {
        XCTAssertEqual(place(body: CGSize(width: 300, height: 32), caption: CGSize(width: 200, height: 18),
                             style: .notch, caret: CGRect(x: 700, y: 925, width: 2, height: 16)).caption,
                       CGRect(x: 656, y: 899, width: 200, height: 18))
    }

    func testWideBodyIsClampedAndStaysOnScreen() {
        let result = place(body: CGSize(width: 900, height: 24), caption: CGSize(width: 400, height: 18))
        XCTAssertEqual(result.body.width, 420)
        XCTAssertGreaterThanOrEqual(result.body.minX, s.visibleFrame.minX)
        XCTAssertLessThanOrEqual(result.body.maxX, s.visibleFrame.maxX)
        XCTAssertEqual(result.caption?.width, 360)
    }

    func testTopPillCaptionIsBelowBody() {
        XCTAssertEqual(place(caption: CGSize(width: 200, height: 18), position: .top).caption,
                       CGRect(x: 656, y: 888, width: 200, height: 18))
    }

    func testDotCaptionIsToTheRightAndVerticallyCentred() {
        let result = place(caption: CGSize(width: 200, height: 18), style: .dot)
        XCTAssertEqual(result.body, CGRect(x: 714, y: 76, width: 84, height: 24))
        XCTAssertEqual(result.caption, CGRect(x: 804, y: 79, width: 200, height: 18))
    }

    func testCaptionAloneCanTriggerEdgeFlip() {
        let result = place(caption: CGSize(width: 200, height: 18),
                           caret: CGRect(x: 700, y: 110, width: 2, height: 10))
        XCTAssertEqual(result.body, CGRect(x: 714, y: 912, width: 84, height: 24))
        XCTAssertEqual(result.caption, CGRect(x: 656, y: 888, width: 200, height: 18))
    }

    func testTopDotFlipsToBottom() {
        XCTAssertEqual(place(style: .dot, position: .top,
                             caret: CGRect(x: 700, y: 920, width: 2, height: 16)).body,
                       CGRect(x: 714, y: 76, width: 84, height: 24))
    }

    func testCaretBodyAndCaptionShiftIndependentlyInsideVisibleFrame() {
        let result = place(caption: CGSize(width: 200, height: 18), style: .dot, position: .caret,
                           caret: CGRect(x: 1500, y: 500, width: 0, height: 18))
        XCTAssertEqual(result.body, CGRect(x: 1428, y: 468, width: 84, height: 24))
        XCTAssertEqual(result.caption, CGRect(x: 1312, y: 471, width: 200, height: 18))
        let left = place(position: .caret, caret: CGRect(x: 1, y: 500, width: 0, height: 18))
        XCTAssertEqual(left.body.minX, 0)
    }

    func testInvalidCaretPlacementFallsBackToBottom() {
        XCTAssertEqual(place(position: .caret, caret: .zero).body,
                       CGRect(x: 714, y: 76, width: 84, height: 24))
    }

    func testNotchUsesFrameCentreWithoutNotchAndIgnoresPosition() {
        let screen = ScreenGeometry(frame: CGRect(x: -1000, y: -200, width: 1000, height: 800),
                                    visibleFrame: CGRect(x: -1000, y: -180, width: 1000, height: 740),
                                    notch: nil)
        let result = IndicatorLayout.place(body: CGSize(width: 300, height: 32), caption: nil,
                                           style: .notch, position: .caret, screen: screen, caret: nil)
        XCTAssertEqual(result.body, CGRect(x: -650, y: 568, width: 300, height: 32))
    }

    func testZeroOrOffscreenCaretIsIgnored() {
        for caret in [CGRect.zero, CGRect(x: 5000, y: 5000, width: 2, height: 18),
                      CGRect(x: 400, y: 500, width: 2, height: 0),
                      CGRect(x: CGFloat.nan, y: 500, width: 2, height: 18)] {
            XCTAssertNil(IndicatorLayout.usableCaret(caret, screens: [s]))
        }
        for width: CGFloat in [2, 0] {
            let caret = CGRect(x: 400, y: 500, width: width, height: 18)
            XCTAssertEqual(IndicatorLayout.usableCaret(caret, screens: [s]), caret)
        }
        XCTAssertNil(IndicatorLayout.usableCaret(nil, screens: [s]))
    }

    func testScreenChoice() {
        let secondFrame = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let screens = [s, ScreenGeometry(frame: secondFrame, visibleFrame: secondFrame, notch: nil)]
        let pointer = CGPoint(x: 2000, y: 500)
        XCTAssertEqual(IndicatorLayout.screenIndex(screens: screens, display: .pointer, position: .bottom,
                                                  pointer: pointer, caret: nil), 1)
        XCTAssertEqual(IndicatorLayout.screenIndex(screens: screens, display: .main, position: .bottom,
                                                  pointer: pointer, caret: nil), 0)
        XCTAssertEqual(IndicatorLayout.screenIndex(screens: screens, display: .main, position: .caret,
                                                  pointer: .zero,
                                                  caret: CGRect(x: 2000, y: 500, width: 0, height: 18)), 1)
        XCTAssertEqual(IndicatorLayout.screenIndex(screens: screens, display: .pointer, position: .bottom,
                                                  pointer: CGPoint(x: -500, y: -500), caret: nil), 0)
        XCTAssertNil(IndicatorLayout.screenIndex(screens: [], display: .pointer, position: .bottom,
                                                pointer: pointer, caret: nil))
    }
}

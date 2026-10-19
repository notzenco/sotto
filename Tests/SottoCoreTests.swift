import XCTest
@testable import SottoCore

final class FormatterTests: XCTestCase {
    func testProseDropsFillersAndAddsPunctuation() {
        let text = TranscriptFormatter.format(
            "um hello period this is sotto",
            mode: .prose
        )
        XCTAssertEqual(text, "Hello. This is sotto")
    }

    func testProseQuestion() {
        let text = TranscriptFormatter.format(
            "hey comma can you ship it question mark",
            mode: .prose
        )
        XCTAssertEqual(text, "Hey, can you ship it?")
    }

    func testProseKeepsExistingCapitalization() {
        let text = TranscriptFormatter.format("Hello.", mode: .prose)
        XCTAssertEqual(text, "Hello.")
    }

    func testProseEmptyAfterFillers() {
        XCTAssertEqual(TranscriptFormatter.format("um uh", mode: .prose), "")
    }

    func testLiteralSymbols() {
        XCTAssertEqual(TranscriptFormatter.format("file dot txt", mode: .literal), "file.txt")
        XCTAssertEqual(TranscriptFormatter.format("word dot", mode: .literal), "dot")
        XCTAssertEqual(
            TranscriptFormatter.format("const underscore name", mode: .literal),
            "const_name"
        )
        XCTAssertEqual(
            TranscriptFormatter.format("open paren value close paren", mode: .literal),
            "(value)"
        )
        XCTAssertEqual(
            TranscriptFormatter.format("hello comma world", mode: .literal),
            "hello, world"
        )
    }

    func testLiteralKeepsFillers() {
        XCTAssertEqual(TranscriptFormatter.format("um stays", mode: .literal), "um stays")
    }
}

final class RulebookTests: XCTestCase {
    func testReplacesWholeWords() {
        let book = Rulebook().remember(heard: "john", written: "Jonathan")
        XCTAssertEqual(book.applying(to: "see john tomorrow"), "see Jonathan tomorrow")
    }

    func testPossessiveFollowsTheName() {
        let book = Rulebook().remember(heard: "john", written: "Bob")
        XCTAssertEqual(book.applying(to: "John's desk"), "Bob's desk")
    }

    func testLongerPhraseWins() {
        var book = Rulebook()
        book = book.remember(heard: "york", written: "Yorkshire")
        book = book.remember(heard: "new york", written: "New York")
        XCTAssertEqual(book.applying(to: "new york"), "New York")
    }

    func testDeletedPhraseIsNotRemembered() {
        var book = Rulebook().remember(heard: "sotto", written: "Sotto")
        let id = book.replacements[0].id
        book = book.delete(id: id)
        book = book.remember(heard: "sotto", written: "Sotto")
        XCTAssertTrue(book.replacements.isEmpty)
    }
}

final class InsertPlannerTests: XCTestCase {
    func testSecureFieldIsRefused() {
        let focus = FocusSnapshot(
            pid: 10, bundleID: "com.apple.Safari",
            selectedTextSettable: true, isSecureField: true, secureInput: true
        )
        XCTAssertEqual(InsertPlanner.route(captured: focus, nowPID: 10), .refuse(.secureField))
    }

    func testFocusChangeIsRefused() {
        let focus = FocusSnapshot(
            pid: 10, bundleID: "com.apple.TextEdit",
            selectedTextSettable: true, isSecureField: false, secureInput: false
        )
        XCTAssertEqual(InsertPlanner.route(captured: focus, nowPID: 11), .refuse(.focusChanged))
    }

    func testTerminalIsTyped() {
        let focus = FocusSnapshot(
            pid: 10, bundleID: "com.apple.Terminal",
            selectedTextSettable: true, isSecureField: false, secureInput: false
        )
        XCTAssertEqual(InsertPlanner.route(captured: focus, nowPID: 10), .unicode)
    }

    func testEditorPastes() {
        let focus = FocusSnapshot(
            pid: 10, bundleID: "com.microsoft.VSCode",
            selectedTextSettable: true, isSecureField: false, secureInput: false
        )
        XCTAssertEqual(
            InsertPlanner.route(captured: focus, nowPID: 10),
            .paste(restoreNanoseconds: 2_000_000_000)
        )
    }

    func testNativeFieldUsesAccessibility() {
        let focus = FocusSnapshot(
            pid: 10, bundleID: "com.apple.TextEdit",
            selectedTextSettable: true, isSecureField: false, secureInput: false
        )
        XCTAssertEqual(InsertPlanner.route(captured: focus, nowPID: 10), .accessibility)
    }

    func testSecureInputWithoutATextFieldIsRefused() {
        let focus = FocusSnapshot(
            pid: 10, bundleID: "com.apple.TextEdit",
            selectedTextSettable: false, isSecureField: false, secureInput: true
        )
        XCTAssertEqual(InsertPlanner.route(captured: focus, nowPID: 10), .refuse(.secureInput))
    }

    func testSecureInputStillTriesAccessibilityOnANormalField() {
        let focus = FocusSnapshot(
            pid: 10, bundleID: "com.apple.Notes",
            selectedTextSettable: true, isSecureField: false, secureInput: true
        )
        XCTAssertEqual(InsertPlanner.route(captured: focus, nowPID: 10), .accessibility)
    }

    func testMissingFocus() {
        let focus = FocusSnapshot(
            pid: 0, bundleID: nil,
            selectedTextSettable: false, isSecureField: false, secureInput: false
        )
        XCTAssertEqual(InsertPlanner.route(captured: focus, nowPID: 0), .refuse(.noFocus))
    }
}

final class HoldTrackerTests: XCTestCase {
    func testHoldFinishes() {
        var tracker = HoldTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(tracker.hotkeyDown(at: start), .startHold)
        XCTAssertEqual(tracker.hotkeyUp(at: start.addingTimeInterval(0.4)), .finish)
    }

    func testShortTapCancels() {
        var tracker = HoldTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(tracker.hotkeyDown(at: start), .startHold)
        XCTAssertEqual(tracker.hotkeyUp(at: start.addingTimeInterval(0.1)), .cancel)
    }

    func testDoubleTapLocksUntilTheNextPress() {
        var tracker = HoldTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(tracker.hotkeyDown(at: start), .startHold)
        XCTAssertEqual(tracker.hotkeyUp(at: start.addingTimeInterval(0.1)), .cancel)
        XCTAssertEqual(tracker.hotkeyDown(at: start.addingTimeInterval(0.2)), .startLocked)
        XCTAssertEqual(tracker.hotkeyUp(at: start.addingTimeInterval(0.28)), .ignore)
        XCTAssertEqual(tracker.hotkeyDown(at: start.addingTimeInterval(2)), .finish)
        XCTAssertEqual(tracker.hotkeyUp(at: start.addingTimeInterval(2.1)), .ignore)
    }

    func testChordCancelsTheHold() {
        var tracker = HoldTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(tracker.hotkeyDown(at: start), .startHold)
        XCTAssertEqual(tracker.chordKey(), .cancel)
        XCTAssertEqual(tracker.hotkeyUp(at: start.addingTimeInterval(0.3)), .ignore)
    }

    func testEscapeCancels() {
        var tracker = HoldTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = tracker.hotkeyDown(at: start)
        XCTAssertEqual(tracker.escape(), .cancel)
        XCTAssertEqual(tracker.escape(), .ignore)
    }
}

final class DestinationTests: XCTestCase {
    func testTerminalIsLiteral() {
        XCTAssertEqual(AppIdentity.defaultMode(bundleID: "com.apple.Terminal", domain: nil), .literal)
    }

    func testEditorIsLiteral() {
        XCTAssertEqual(AppIdentity.defaultMode(bundleID: "com.microsoft.VSCode", domain: nil), .literal)
    }

    func testMailIsProse() {
        XCTAssertEqual(AppIdentity.defaultMode(bundleID: "com.apple.mail", domain: nil), .prose)
    }

    func testGmailDomainIsProseEmail() {
        XCTAssertEqual(
            AppIdentity.classify(bundleID: "com.google.Chrome", domain: "mail.google.com"),
            .email
        )
        XCTAssertEqual(
            AppIdentity.defaultMode(bundleID: "com.google.Chrome", domain: "mail.google.com"),
            .prose
        )
    }

    func testBareBrowserIsProse() {
        XCTAssertEqual(AppIdentity.defaultMode(bundleID: "com.google.Chrome", domain: nil), .prose)
    }
}

final class RightCommandTests: XCTestCase {
    func testDeviceBitWinsOverKeycode() {
        XCTAssertEqual(RightCommand.isDown(flags: 0x10, keyCode: 0), true)
        XCTAssertEqual(RightCommand.isDown(flags: 0x08, keyCode: 54), false)
        XCTAssertEqual(RightCommand.isDown(flags: 0x18, keyCode: 56), true)
    }

    func testKeycodeWhenTheKeyboardOmitsDeviceBits() {
        XCTAssertEqual(RightCommand.isDown(flags: RightCommand.commandMask, keyCode: 54), true)
        XCTAssertEqual(RightCommand.isDown(flags: 0, keyCode: 54), false)
        XCTAssertNil(RightCommand.isDown(flags: RightCommand.commandMask, keyCode: 0))
    }

    func testHeldStateUsesTheRightDeviceBit() {
        XCTAssertTrue(RightCommand.isHeld(modifierRaw: 0x10, keyIsDown: false))
        XCTAssertTrue(RightCommand.isHeld(modifierRaw: 0x00100010, keyIsDown: false))
        XCTAssertFalse(RightCommand.isHeld(modifierRaw: 0x08, keyIsDown: true))
        XCTAssertFalse(RightCommand.isHeld(modifierRaw: RightCommand.commandMask, keyIsDown: false))
        XCTAssertTrue(RightCommand.isHeld(modifierRaw: 0, keyIsDown: true))
        XCTAssertFalse(RightCommand.isHeld(modifierRaw: 0, keyIsDown: false))
    }
}

final class PreRollTests: XCTestCase {
    func testDropsSamplesOlderThanTheWindow() {
        var roll = PreRoll(capacity: 4)
        roll.append([1, 2, 3])
        roll.append([4, 5])
        XCTAssertEqual(roll.snapshot(), [2, 3, 4, 5])
    }
}

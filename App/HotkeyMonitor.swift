import AppKit
import CoreGraphics
import SottoCore

/// Listens for Right Command (keycode 54) and Escape.
///
/// The tap is listen-only, so it does not swallow the key. It can be created without
/// Accessibility, but macOS only delivers keys to it once Accessibility is on.
/// A custom shortcut from KeyboardShortcuts is handled separately.
final class HotkeyMonitor {
    var onRightCommand: (@Sendable (Bool) -> Void)?
    var onEscape: (@Sendable () -> Void)?
    var onChord: (@Sendable () -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var rightCommandIsDown = false

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        rightCommandIsDown = false
    }

    var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func reenableIfNeeded() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func markRightCommand(_ down: Bool) {
        rightCommandIsDown = down
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        // Stay off AppKit here. NSEvent(cgEvent:) inside the tap callback gets the tap disabled.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            let flags = UInt64(event.flags.rawValue)
            guard let down = RightCommand.isDown(flags: flags, keyCode: keyCode) else { return }
            guard down != rightCommandIsDown else { return }
            rightCommandIsDown = down
            let callback = onRightCommand
            DispatchQueue.main.async { callback?(down) }
            return
        }
        if type == .keyDown, keyCode == Self.escapeKeyCode {
            let callback = onEscape
            DispatchQueue.main.async { callback?() }
            return
        }
        if type == .keyDown, rightCommandIsDown, keyCode != RightCommand.keyCode {
            let callback = onChord
            DispatchQueue.main.async { callback?() }
        }
    }

    private static let escapeKeyCode: Int64 = 53
}

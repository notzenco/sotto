import Foundation

/// Press and release of the dictation key.
///
/// A press shorter than 180 ms is discarded so a stray tap does not insert.
/// Two discarded taps inside 350 ms lock hands-free listening. The next press finishes it.
/// A second key while the dictation key is held is a shortcut, and the take is dropped.
public struct HoldTracker: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case startHold
        case startLocked
        case finish
        case cancel
        case ignore
    }

    public static let tapCeiling: TimeInterval = 0.18
    public static let doubleTapWindow: TimeInterval = 0.35

    private var listening = false
    private var locked = false
    private var downAt: Date?
    private var lastIgnoredTap: Date?
    private var suppressUntilUp = false

    public init() {}

    public var isListening: Bool { listening }
    public var isLocked: Bool { locked }

    public mutating func hotkeyDown(at time: Date) -> Event {
        if suppressUntilUp { return .ignore }
        if locked {
            suppressUntilUp = true
            locked = false
            listening = false
            downAt = nil
            lastIgnoredTap = nil
            return .finish
        }
        if listening { return .ignore }
        if let lastIgnoredTap, time.timeIntervalSince(lastIgnoredTap) <= Self.doubleTapWindow {
            listening = true
            locked = true
            downAt = time
            self.lastIgnoredTap = nil
            return .startLocked
        }
        listening = true
        locked = false
        downAt = time
        return .startHold
    }

    public mutating func hotkeyUp(at time: Date) -> Event {
        if suppressUntilUp {
            suppressUntilUp = false
            return .ignore
        }
        guard listening else { return .ignore }
        if locked {
            downAt = nil
            return .ignore
        }
        let started = downAt ?? time
        let duration = time.timeIntervalSince(started)
        listening = false
        downAt = nil
        if duration < Self.tapCeiling {
            lastIgnoredTap = time
            return .cancel
        }
        lastIgnoredTap = nil
        return .finish
    }

    public mutating func chordKey() -> Event {
        guard listening, !locked else { return .ignore }
        listening = false
        downAt = nil
        lastIgnoredTap = nil
        return .cancel
    }

    public mutating func escape() -> Event {
        guard listening || locked else { return .ignore }
        listening = false
        locked = false
        downAt = nil
        lastIgnoredTap = nil
        suppressUntilUp = false
        return .cancel
    }
}

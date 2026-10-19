import Foundation

/// Right Command is keycode 54. The event also carries the device bit NX_DEVICERCMDKEYMASK (0x10).
/// A flags-changed event often arrives with keycode 0, so the device bit is the reliable signal.
public enum RightCommand {
    public static let keyCode: Int64 = 54
    public static let deviceMask: UInt64 = 0x10
    public static let leftDeviceMask: UInt64 = 0x08
    public static let commandMask: UInt64 = 0x00100000

    /// Whether the right command key is down. Nil when this event does not say.
    public static func isDown(flags: UInt64, keyCode: Int64) -> Bool? {
        let deviceRight = flags & deviceMask != 0
        let deviceLeft = flags & leftDeviceMask != 0
        if deviceRight || deviceLeft {
            return deviceRight
        }
        if keyCode == Self.keyCode {
            return flags & commandMask != 0
        }
        return nil
    }

    /// Live state. Device bits come from `NSEvent.modifierFlags`. A keyboard that omits them falls back to keycode 54.
    /// The generic command flag is not enough: that is also the left command key.
    public static func isHeld(modifierRaw: UInt64, keyIsDown: Bool) -> Bool {
        let deviceRight = modifierRaw & deviceMask != 0
        let deviceLeft = modifierRaw & leftDeviceMask != 0
        if deviceRight || deviceLeft {
            return deviceRight
        }
        return keyIsDown
    }
}

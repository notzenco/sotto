import Foundation

public enum InsertFailure: String, Equatable, Sendable {
    case secureField
    case secureInput
    case focusChanged
    case noFocus
}

public enum InsertRoute: Equatable, Sendable {
    case refuse(InsertFailure)
    /// Write the selected-text attribute, then read it back.
    case accessibility
    /// Borrow the clipboard. `restoreNanoseconds` is how long to wait before putting it back.
    case paste(restoreNanoseconds: UInt64)
    /// Type the text. Used for terminals, where a paste wedges the program.
    case unicode
}

public struct FocusSnapshot: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var selectedTextSettable: Bool
    public var isSecureField: Bool
    public var secureInput: Bool

    public init(
        pid: Int32,
        bundleID: String?,
        selectedTextSettable: Bool,
        isSecureField: Bool,
        secureInput: Bool
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.selectedTextSettable = selectedTextSettable
        self.isSecureField = isSecureField
        self.secureInput = secureInput
    }
}

public enum InsertPlanner {
    public static func route(captured: FocusSnapshot, nowPID: Int32) -> InsertRoute {
        if captured.pid == 0 { return .refuse(.noFocus) }
        if nowPID != captured.pid { return .refuse(.focusChanged) }
        if captured.isSecureField { return .refuse(.secureField) }
        if captured.secureInput {
            if captured.selectedTextSettable { return .accessibility }
            return .refuse(.secureInput)
        }
        if AppIdentity.isTerminal(captured.bundleID ?? "") { return .unicode }
        if AppIdentity.prefersPaste(captured.bundleID) {
            return .paste(restoreNanoseconds: AppIdentity.pasteRestoreNanoseconds(bundleID: captured.bundleID))
        }
        if captured.selectedTextSettable { return .accessibility }
        return .paste(restoreNanoseconds: AppIdentity.pasteRestoreNanoseconds(bundleID: captured.bundleID))
    }
}

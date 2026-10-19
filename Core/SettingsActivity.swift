/// Retained Settings content must release work when its window becomes hidden.
public struct SettingsActivity: Equatable, Sendable {
    public var windowVisible = false
    public var microphoneSelected = false

    public init() {}

    public var watchesMeter: Bool { windowVisible && microphoneSelected }
}

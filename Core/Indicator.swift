import Foundation

public enum TakeProblem: String, Equatable, Sendable {
    case notHeard
    case passwordField
    case focusMoved
    case noTextField
    case couldNotType
    case accessibilityOff
    case microphoneOff
    case modelDownloading

    public var message: String {
        switch self {
        case .notHeard: "Didn't catch that"
        case .passwordField: "Won't type into a password field"
        case .focusMoved: "You moved away, so it's kept for Copy Last"
        case .noTextField: "No text field, so it's kept for Copy Last"
        case .couldNotType: "Couldn't type here, so it's kept for Copy Last"
        case .accessibilityOff: "Turn on Accessibility for Sotto"
        case .microphoneOff: "Turn on Microphone for Sotto"
        case .modelDownloading: "Still downloading the speech model"
        }
    }
}

public enum IndicatorPhase: Equatable, Sendable {
    case hidden
    case listening(handsFree: Bool)
    case working
    case done
    case problem(TakeProblem)
    case cancelled

    public var linger: TimeInterval? {
        switch self {
        case .hidden, .listening, .working: nil
        case .done: 0.9
        case .problem: 4
        case .cancelled: 0
        }
    }
}

public struct IndicatorSchedule: Sendable {
    public private(set) var phase: IndicatorPhase = .hidden
    public private(set) var generation: Int = 0

    public init() {}

    public mutating func show(_ phase: IndicatorPhase) -> Int {
        generation += 1
        self.phase = phase
        return generation
    }

    public mutating func expire(_ generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        phase = .hidden
        return true
    }
}

import Foundation

public enum DictationMode: String, Codable, Sendable, CaseIterable, Equatable {
    case prose
    case literal

    public var label: String {
        switch self {
        case .prose: "Prose"
        case .literal: "Literal"
        }
    }
}

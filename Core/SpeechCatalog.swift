import Foundation

public enum SpeechModelID: String, Codable, CaseIterable, Sendable {
    case parakeetV2, parakeetUltra, phonon2, parakeetV3, cohere, appleEnglish
}

public enum SpeechEngineKind: String, Sendable {
    case parakeet, cohere, apple
}

public struct SpeechModelInfo: Equatable, Sendable {
    public let id: SpeechModelID
    public let name: String
    public let summary: String
    /// Nil for models built into macOS, which need no download.
    public let approximateMegabytes: Int?
    public let kind: SpeechEngineKind
    public let acceptsHints: Bool
    /// Licence credit shown in About. Empty for Apple's built-in engine.
    public let credit: String
}

public enum SpeechCatalog {
    /// Every model Sotto offers, in the order the Speech pane lists them.
    public static let all: [SpeechModelInfo] = [
        SpeechModelInfo(
            id: .parakeetV2,
            name: "Parakeet TDT 0.6B v2",
            summary: "Today's model and the default. English.",
            approximateMegabytes: 470,
            kind: .parakeet,
            acceptsHints: true,
            credit: "NVIDIA Parakeet TDT 0.6B v2 (CC-BY-4.0), via FluidAudio."
        ),
        SpeechModelInfo(
            id: .parakeetUltra,
            name: "Parakeet Ultra",
            summary: "FluidAudio's most accurate Parakeet.",
            approximateMegabytes: 630,
            kind: .parakeet,
            acceptsHints: true,
            credit: "Moondream Parakeet Ultra (CC-BY-4.0), via FluidAudio."
        ),
        SpeechModelInfo(
            id: .phonon2,
            name: "Phonon-2",
            summary: "Fastest Parakeet. English only.",
            approximateMegabytes: 360,
            kind: .parakeet,
            acceptsHints: true,
            credit: "Fermion Research Phonon-2 (CC-BY-4.0), based on NVIDIA Parakeet TDT 0.6B v3, via FluidAudio."
        ),
        SpeechModelInfo(
            id: .parakeetV3,
            name: "Parakeet TDT 0.6B v3",
            summary: "25 languages, more varied training voices.",
            approximateMegabytes: 480,
            kind: .parakeet,
            acceptsHints: true,
            credit: "NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0), via FluidAudio."
        ),
        SpeechModelInfo(
            id: .cohere,
            name: "Cohere Transcribe",
            summary: "Near the top of the public English accuracy leaderboard. Slower.",
            approximateMegabytes: 1800,
            kind: .cohere,
            acceptsHints: false,
            credit: "Cohere Labs Cohere Transcribe 03-2026 (Apache-2.0), via FluidAudio."
        ),
        SpeechModelInfo(
            id: .appleEnglish,
            name: "Apple English",
            summary: "Built into macOS. Follows the spelling setting's English.",
            approximateMegabytes: nil,
            kind: .apple,
            acceptsHints: true,
            credit: ""
        ),
    ]

    public static func info(_ id: SpeechModelID) -> SpeechModelInfo {
        // `all` lists every case, so the lookup always succeeds.
        all.first { $0.id == id }!
    }
}

public enum SpellingVariety: String, Codable, CaseIterable, Sendable {
    case australian, british, american

    public var localeIdentifier: String {
        switch self {
        case .australian: "en_AU"
        case .british: "en_GB"
        case .american: "en_US"
        }
    }

    public var label: String {
        switch self {
        case .australian: "Australian"
        case .british: "British"
        case .american: "American"
        }
    }
}

/// A word the typing model listens for, with the misheard forms it replaces.
public struct HintTerm: Codable, Equatable, Sendable {
    public var text: String
    public var aliases: [String]

    public init(text: String, aliases: [String] = []) {
        self.text = text
        self.aliases = aliases
    }
}

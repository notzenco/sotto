import Foundation
import SottoCore

enum ModelPhase: Equatable, Sendable {
    case missing
    case downloading
    case ready
    case failed(String)
}

enum ModelState: Equatable, Sendable {
    case notDownloaded
    /// The download fraction in 0...1, or nil before it is known.
    case downloading(Double?)
    /// Compiling for the Neural Engine and loading into memory.
    case preparing
    /// Downloaded and usable. Only the typing model is kept loaded.
    case ready
    case failed(String)
}

struct EngineResult: Equatable, Sendable {
    /// What the model heard before hint words were applied.
    var raw: String
    var hinted: String
}

protocol SpeechEngine: Actor {
    nonisolated var id: SpeechModelID { get }
    /// Async because Apple reports its installed locales asynchronously.
    func isDownloaded() async -> Bool
    /// Downloads the model if needed and loads it. `progress` reports the download fraction in 0...1,
    /// then nil once the model is compiling. It is called on an arbitrary queue.
    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws
    var isLoaded: Bool { get }
    /// 16 kHz mono floats. Returns nil when the take is too short, empty, or invalid.
    func transcribe(_ samples: [Float], hints: [HintTerm]) async throws -> EngineResult?
    func unload()
    func deleteFiles() throws
}

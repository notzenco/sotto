import FluidAudio
import Foundation
import SottoCore
import Synchronization

/// Every Parakeet version FluidAudio ships loads and decodes the same way; only the weights differ.
actor ParakeetFamilyEngine: SpeechEngine {
    nonisolated let id: SpeechModelID
    private let version: AsrModelVersion

    private var manager: AsrManager?
    private var preparation: Task<AsrManager, any Error>?

    init(id: SpeechModelID, version: AsrModelVersion) {
        self.id = id
        self.version = version
    }

    var isLoaded: Bool { manager != nil }

    func isDownloaded() -> Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }

    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws {
        if manager != nil { return }
        if let preparation {
            _ = try await preparation.value
            return
        }
        let version = version
        let handler = Self.progressHandler(progress)
        let task = Task { () throws -> AsrManager in
            let models = try await AsrModels.downloadAndLoad(
                to: nil, configuration: nil, version: version, progressHandler: handler)
            let manager = AsrManager()
            try await manager.loadModels(models)
            return manager
        }
        preparation = task
        defer { preparation = nil }
        manager = try await task.value
    }

    func transcribe(_ samples: [Float], hints: [HintTerm]) async throws -> EngineResult? {
        guard samples.count >= 1600, samples.allSatisfy({ $0.isFinite }) else { return nil }
        guard let manager else { throw EngineError.notReady }

        do {
            let result = try await manager.transcribeFresh(samples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : EngineResult(raw: text, hinted: text)
        } catch ASRError.invalidAudioData {
            return nil
        }
    }

    /// Drops the models without `cleanup()`, so a transcription already running on them can finish.
    func unload() {
        manager = nil
    }

    func deleteFiles() throws {
        let directory = AsrModels.defaultCacheDirectory(for: version)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// FluidAudio's download fraction covers 0...0.5 of a repo load, and every model file it loads
    /// reports a cached download again before compiling. Compiling is reported once, as nil, and nothing after it.
    /// Byte updates arrive per network write, so the fraction is only passed on when it moves by 0.01.
    /// CohereEngine shares it: `ModelHub.download` weights its fraction the same way.
    static func progressHandler(_ progress: @escaping @Sendable (Double?) -> Void) -> ProgressHandler {
        let gate = ProgressGate()
        return { update in
            let report: Double?? = gate.state.withLock { state in
                let phase: ProgressGate.Phase
                let fraction: Double?
                switch update.phase {
                case .compiling:
                    phase = .compiling
                    fraction = nil
                case .listing:
                    phase = .listing
                    fraction = 0
                case .downloading(_, let totalFiles) where totalFiles > 0:
                    phase = .downloading
                    fraction = min(update.fractionCompleted * 2, 1)
                case .downloading:
                    return .none
                }
                if state.phase == .compiling { return .none }
                if phase == state.phase, let fraction, let last = state.fraction,
                   fraction - last < 0.01, fraction < 1 {
                    return .none
                }
                state.phase = phase
                state.fraction = fraction
                return .some(fraction)
            }
            if case .some(let fraction) = report {
                progress(fraction)
            }
        }
    }

    private enum EngineError: Error {
        case notReady
    }

    private final class ProgressGate: Sendable {
        enum Phase { case none, listing, downloading, compiling }
        struct State {
            var phase = Phase.none
            var fraction: Double?
        }
        let state = Mutex(State())
    }
}

extension AsrManager {
    /// Each take decodes from a fresh state.
    func transcribeFresh(_ samples: [Float]) async throws -> ASRResult {
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        return try await transcribe(samples, decoderState: &state)
    }
}

import FluidAudio
import Foundation

enum ModelPhase: Equatable, Sendable {
    case missing
    case downloading
    case ready
    case failed(String)
}

actor ParakeetEngine {
    private(set) var phase: ModelPhase = .missing

    private var manager: AsrManager?
    private var preparationTask: Task<Void, Never>?

    /// Downloads and compiles Parakeet TDT 0.6B v2 on first call. Later calls return the current phase.
    func prepare() async -> ModelPhase {
        if let preparationTask {
            await preparationTask.value
            return phase
        }
        if case .ready = phase { return phase }
        phase = .downloading

        let task = Task {
            do {
                let models = try await AsrModels.downloadAndLoad(version: .v2)
                let manager = AsrManager()
                try await manager.loadModels(models)
                self.manager = manager
                phase = .ready
            } catch {
                phase = .failed(String(error.localizedDescription.prefix(200)))
            }
        }
        preparationTask = task
        await task.value
        preparationTask = nil
        return phase
    }

    /// 16 kHz mono floats. Returns trimmed text, or nil when the take is too short, empty, or invalid.
    func transcribe(_ samples: [Float]) async throws -> String? {
        guard samples.count >= 1600, samples.allSatisfy({ $0.isFinite }) else { return nil }
        guard phase == .ready, let manager else { throw EngineError.notReady }

        do {
            let result = try await manager.transcribeEnglish(samples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch ASRError.invalidAudioData {
            return nil
        }
    }

    private enum EngineError: Error {
        case notReady
    }
}

extension AsrManager {
    func transcribeEnglish(_ samples: [Float]) async throws -> ASRResult {
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        return try await transcribe(samples, decoderState: &state)
    }
}

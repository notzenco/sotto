import FluidAudio
import Foundation
import OSLog
import SottoCore

/// Cohere Transcribe: the large, accurate model used as the teacher and as a Compare candidate.
/// It has no hint support, so `raw` and `hinted` are always the same.
actor CohereEngine: SpeechEngine {
    nonisolated let id: SpeechModelID

    /// FluidAudio defaults to the 256-slot v3 decoder, but the FluidInference repo only publishes
    /// v1 and v2 (checked 2026-10-19), so a default download ends in "Model file not found".
    /// v2 caps each 35 s window at 99 tokens; switch both values once v3 is published.
    private static let decoderVariant = CoherePipeline.DecoderVariant.v2
    private static let downloadVariant = "v2"

    private let log = Logger(subsystem: "app.sotto.desktop", category: "dictation")
    private var loaded: Loaded?
    private var preparation: Task<Loaded, any Error>?

    init(id: SpeechModelID) {
        self.id = id
    }

    var isLoaded: Bool { loaded != nil }

    func isDownloaded() -> Bool {
        let folder = Self.modelFolder
        return Self.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// The first load in each process compiles for the Neural Engine for about 3 minutes;
    /// that whole time is reported as nil.
    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws {
        if loaded != nil { return }
        if let preparation {
            _ = try await preparation.value
            return
        }
        let needsDownload = !isDownloaded()
        let handler = ParakeetFamilyEngine.progressHandler(progress)
        let task = Task { () throws -> Loaded in
            if needsDownload {
                try await ModelHub.download(
                    .cohereTranscribeCoreml, to: MLModelConfigurationUtils.defaultModelsDirectory(),
                    variant: Self.downloadVariant, progressHandler: handler)
            }
            progress(nil)
            let folder = Self.modelFolder
            let models = try await CoherePipeline.loadModels(
                encoderDir: folder, decoderDir: folder, vocabDir: folder,
                decoderVariant: Self.decoderVariant)
            return Loaded(models: models, pipeline: CoherePipeline())
        }
        preparation = task
        defer { preparation = nil }
        loaded = try await task.value
    }

    func transcribe(_ samples: [Float], hints: [HintTerm]) async throws -> EngineResult? {
        guard samples.count >= 1600, samples.allSatisfy({ $0.isFinite }) else { return nil }
        guard let loaded else { throw EngineError.notReady }

        do {
            let result = try await loaded.pipeline.transcribeLong(
                audio: samples, models: loaded.models, language: .english)
            // A capped window dropped its tail; the teacher would align the missing words as wrong ones.
            guard result.cappedWindows == 0 else {
                log.notice("cohere result capped in \(result.cappedWindows, privacy: .public) window(s); clip skipped")
                return nil
            }
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : EngineResult(raw: text, hinted: text)
        } catch CohereAsrError.invalidInput {
            return nil
        }
    }

    /// FluidAudio has no unload call; dropping the references frees the models once
    /// a transcription already running on them finishes.
    func unload() {
        loaded = nil
    }

    func deleteFiles() throws {
        let directory = MLModelConfigurationUtils.defaultModelsDirectory()
            .appendingPathComponent("cohere-transcribe", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// `<models>/cohere-transcribe/q8`, which holds the encoder, decoder and vocabulary.
    private static var modelFolder: URL {
        MLModelConfigurationUtils.defaultModelsDirectory(for: .cohereTranscribeCoreml)
    }

    private static var requiredFiles: [String] {
        [
            ModelNames.CohereTranscribe.encoderCompiledFile,
            decoderVariant.compiledFileName,
            ModelNames.CohereTranscribe.vocab,
        ]
    }

    private struct Loaded: Sendable {
        let models: CoherePipeline.LoadedModels
        let pipeline: CoherePipeline
    }

    private enum EngineError: Error {
        case notReady
    }
}

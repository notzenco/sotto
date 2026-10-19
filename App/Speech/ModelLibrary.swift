import Foundation
import Observation
import SottoCore

enum ModelLibraryError: LocalizedError {
    case inUse
    case unavailable
    case busy
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .inUse: "This model is typing. Choose another model first."
        case .unavailable: "Sotto can't run this model yet."
        case .busy: "This model is downloading or preparing."
        case .notReady(let reason): reason
        }
    }
}

/// Owns every speech engine. Only the typing model stays loaded; other models load for a job and unload after it.
@MainActor
@Observable
final class ModelLibrary {
    private(set) var states: [SpeechModelID: ModelState] = [:]
    private(set) var typingModel: SpeechModelID

    private var spelling: SpellingVariety
    private var engines: [SpeechModelID: any SpeechEngine]
    /// The loaded engine dictation uses. Nil until the typing model is ready.
    private var typingEngine: (any SpeechEngine)?
    /// The model the latest `select` is switching to.
    private var pendingSelection: SpeechModelID?
    private var loading: [SpeechModelID: Task<Bool, Never>] = [:]
    /// Models whose download or load is running, so late progress updates are ignored.
    private var inFlight: Set<SpeechModelID> = []

    /// Falls back to Parakeet v2 when the saved typing model has no engine in this build.
    init(typingModel: SpeechModelID, spelling: SpellingVariety) {
        var engines: [SpeechModelID: any SpeechEngine] = [:]
        for id in SpeechModelID.allCases {
            engines[id] = makeEngine(for: id, spelling: spelling)
        }
        self.engines = engines
        self.spelling = spelling
        self.typingModel = engines[typingModel] == nil ? .parakeetV2 : typingModel
    }

    /// Maps the typing model's state for callers that predate the model library.
    var typingPhase: ModelPhase {
        switch states[typingModel] {
        case .ready?: typingEngine == nil ? .downloading : .ready
        case .downloading?, .preparing?: .downloading
        case .failed(let reason)?: .failed(reason)
        case .notDownloaded?, nil: .missing
        }
    }

    /// Rebuilds the Apple engine, if any, for the new locale.
    func setSpelling(_ variety: SpellingVariety) {
        guard variety != spelling else { return }
        spelling = variety
        guard let old = engines[.appleEnglish] else { return }
        engines[.appleEnglish] = makeEngine(for: .appleEnglish, spelling: variety)
        states[.appleEnglish] = nil
        Task { await old.unload() }
        guard typingModel == .appleEnglish else { return }
        typingEngine = nil
        Task { await prepareTypingModel() }
    }

    func refreshDownloadStates() {
        for (id, engine) in engines where !inFlight.contains(id) && engine !== typingEngine {
            let before = states[id]
            Task {
                let downloaded = await engine.isDownloaded()
                // A download, load or delete that finished meanwhile knows better.
                guard !inFlight.contains(id), states[id] == before else { return }
                if case .failed? = before { return }
                states[id] = downloaded ? .ready : .notDownloaded
            }
        }
    }

    /// Downloads the typing model if needed and loads it. Retry calls this again after a failure.
    func prepareTypingModel() async {
        let id = typingModel
        guard let engine = engines[id], await load(id), typingModel == id else { return }
        typingEngine = engine
    }

    /// Keeps typing with the current model until the new one is ready, then switches and unloads the old one.
    /// If the new model fails, typing stays on the current model and the new one shows the failure.
    func select(_ id: SpeechModelID) async {
        if id == typingModel {
            pendingSelection = nil
            if typingEngine == nil { await prepareTypingModel() }
            return
        }
        guard let engine = engines[id] else {
            states[id] = .failed(ModelLibraryError.unavailable.localizedDescription)
            return
        }
        pendingSelection = id
        let ready = await load(id)
        // A later selection replaced this one while it loaded.
        guard pendingSelection == id else {
            await unloadUnlessTyping(id)
            return
        }
        pendingSelection = nil
        guard ready else { return }
        let old = typingEngine
        typingModel = id
        typingEngine = engine
        if let old, old !== engine {
            await old.unload()
        }
    }

    /// Downloads a model without making it the typing model.
    func download(_ id: SpeechModelID) async {
        guard await load(id) else { return }
        await unloadUnlessTyping(id)
    }

    func delete(_ id: SpeechModelID) async throws {
        guard id != typingModel, id != pendingSelection else { throw ModelLibraryError.inUse }
        guard let engine = engines[id] else { throw ModelLibraryError.unavailable }
        guard !inFlight.contains(id) else { throw ModelLibraryError.busy }
        await engine.unload()
        try await engine.deleteFiles()
        states[id] = .notDownloaded
    }

    /// Nil when the typing model isn't ready or hears nothing.
    func transcribeTyping(_ samples: [Float], hints: [HintTerm]) async -> EngineResult? {
        guard let engine = typingEngine else { return nil }
        do { return try await engine.transcribe(samples, hints: hints) }
        catch { return nil }
    }

    /// Loads the model if it isn't the typing model, runs `body`, then unloads it.
    func withLoaded<T: Sendable>(
        _ id: SpeechModelID,
        _ body: @Sendable (any SpeechEngine) async throws -> T
    ) async throws -> T {
        guard let engine = engines[id] else { throw ModelLibraryError.unavailable }
        guard await load(id) else {
            if case .failed(let reason)? = states[id] { throw ModelLibraryError.notReady(reason) }
            throw ModelLibraryError.notReady("The model didn't load.")
        }
        do {
            let result = try await body(engine)
            await unloadUnlessTyping(id)
            return result
        } catch {
            await unloadUnlessTyping(id)
            throw error
        }
    }

    /// Joins a download or load already running for the same model.
    private func load(_ id: SpeechModelID) async -> Bool {
        if let running = loading[id] { return await running.value }
        guard let engine = engines[id] else { return false }
        let task = Task { await run(engine) }
        loading[id] = task
        let ready = await task.value
        loading[id] = nil
        return ready
    }

    private func run(_ engine: any SpeechEngine) async -> Bool {
        let id = engine.id
        inFlight.insert(id)
        if await engine.isLoaded {
            inFlight.remove(id)
            states[id] = .ready
            return true
        }
        states[id] = await engine.isDownloaded() ? .preparing : .downloading(nil)
        do {
            try await engine.prepare { [weak self] fraction in
                Task { @MainActor in self?.noteProgress(id, fraction) }
            }
            inFlight.remove(id)
            states[id] = .ready
            return true
        } catch {
            inFlight.remove(id)
            states[id] = .failed(String(error.localizedDescription.prefix(200)))
            return false
        }
    }

    /// Progress hops arrive in any order, so the state only moves forward.
    private func noteProgress(_ id: SpeechModelID, _ fraction: Double?) {
        guard inFlight.contains(id) else { return }
        switch (states[id], fraction) {
        case (.preparing?, _):
            return
        case (_, nil):
            states[id] = .preparing
        case (.downloading(let shown?)?, let fraction?) where fraction < shown:
            return
        case (_, let fraction?):
            states[id] = .downloading(fraction)
        }
    }

    private func unloadUnlessTyping(_ id: SpeechModelID) async {
        guard id != typingModel, id != pendingSelection, let engine = engines[id] else { return }
        await engine.unload()
    }
}

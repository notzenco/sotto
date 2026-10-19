import Foundation
import Observation
import SottoCore

enum ModelLibraryError: LocalizedError {
    case inUse
    case unavailable
    case busy
    case builtIn
    case notDownloaded
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .inUse: "This model is typing. Choose another model first."
        case .unavailable: "Sotto can't run this model yet."
        case .busy: "This model is downloading or preparing."
        case .builtIn: "This model is built into macOS."
        case .notDownloaded: "Download this model first."
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
    private let hintBooster: HintBooster
    private var engines: [SpeechModelID: any SpeechEngine]
    /// The loaded engine dictation uses. Nil until the typing model is ready.
    private var typingEngine: (any SpeechEngine)?
    /// The model the latest `select` is switching to.
    private var pendingSelection: SpeechModelID?
    /// The running load for each model and the engine it is loading. A spelling change can replace the engine meanwhile.
    private var loading: [SpeechModelID: (engine: any SpeechEngine, task: Task<Bool, Never>)] = [:]
    /// Models whose download or load is running, so late progress updates are ignored.
    private var inFlight: Set<SpeechModelID> = []
    /// Jobs holding each model loaded. Every load takes a lease; the last release unloads a model that isn't typing.
    private var leases: [SpeechModelID: Int] = [:]
    /// A running unload or delete. Loads wait for it, so they never race it.
    private var teardowns: [SpeechModelID: Task<(any Error)?, Never>] = [:]
    /// Engines a spelling change replaced. They unload once no job holds their model, so a Compare or teacher job keeps its engine.
    private var retired: [SpeechModelID: [any SpeechEngine]] = [:]

    /// Falls back to Parakeet v2 when the saved typing model has no engine in this build.
    init(typingModel: SpeechModelID, spelling: SpellingVariety) {
        let hintBooster = HintBooster()
        var engines: [SpeechModelID: any SpeechEngine] = [:]
        for id in SpeechModelID.allCases {
            engines[id] = makeEngine(for: id, spelling: spelling, hintBooster: hintBooster)
        }
        self.hintBooster = hintBooster
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

    /// Rebuilds the Apple engine, if any, for the new locale. The old one unloads once no job holds it.
    func setSpelling(_ variety: SpellingVariety) {
        guard variety != spelling else { return }
        spelling = variety
        guard let old = engines[.appleEnglish] else { return }
        engines[.appleEnglish] = makeEngine(for: .appleEnglish, spelling: variety, hintBooster: hintBooster)
        states[.appleEnglish] = nil
        retired[.appleEnglish, default: []].append(old)
        Task { await unloadRetiredIfIdle(.appleEnglish) }
        guard typingModel == .appleEnglish else { return }
        typingEngine = nil
        Task { await prepareTypingModel() }
    }

    func refreshDownloadStates() {
        for (id, engine) in engines where !inFlight.contains(id) && engine !== typingEngine {
            let before = states[id]
            Task {
                let downloaded = await engine.isDownloaded()
                // A download, load, delete or spelling change that happened meanwhile knows better.
                guard !inFlight.contains(id), states[id] == before, engines[id] === engine else { return }
                if case .failed? = before { return }
                states[id] = downloaded ? .ready : .notDownloaded
            }
        }
    }

    /// Downloads the typing model if needed and loads it. Retry calls this again after a failure.
    func prepareTypingModel() async {
        let id = typingModel
        guard engines[id] != nil else { return }
        if let engine = await acquire(id), typingModel == id {
            typingEngine = engine
        }
        // Unloads the model if a selection replaced it while it loaded.
        await release(id)
    }

    /// Keeps typing with the current model until the new one is ready, then switches and unloads the old one.
    /// If the new model fails, typing stays on the current model and the new one shows the failure.
    func select(_ id: SpeechModelID) async {
        if id == typingModel {
            pendingSelection = nil
            if typingEngine == nil { await prepareTypingModel() }
            return
        }
        guard engines[id] != nil else {
            states[id] = .failed(ModelLibraryError.unavailable.localizedDescription)
            return
        }
        pendingSelection = id
        let loaded = await acquire(id)
        // A later selection may have replaced this one while it loaded; its release then unloads this model.
        if pendingSelection == id {
            pendingSelection = nil
            if let engine = loaded {
                let old = typingModel
                typingModel = id
                typingEngine = engine
                await unloadIfIdle(old)
            }
        }
        await release(id)
    }

    /// Downloads a model without making it the typing model.
    func download(_ id: SpeechModelID) async {
        _ = await acquire(id)
        await release(id)
    }

    /// Refuses Apple's built-in model: macOS keeps its files, so it would only look deleted.
    func delete(_ id: SpeechModelID) async throws {
        guard SpeechCatalog.info(id).kind != .apple else { throw ModelLibraryError.builtIn }
        while let running = teardowns[id] { _ = await running.value }
        // No awaits from these checks until the teardown is registered, so no load can start in between.
        guard id != typingModel, id != pendingSelection else { throw ModelLibraryError.inUse }
        guard let engine = engines[id] else { throw ModelLibraryError.unavailable }
        guard leases[id] == nil, !inFlight.contains(id) else { throw ModelLibraryError.busy }
        let task = Task { () -> (any Error)? in
            defer { teardowns[id] = nil }
            await engine.unload()
            do {
                try await engine.deleteFiles()
                states[id] = .notDownloaded
                return nil
            } catch {
                return error
            }
        }
        teardowns[id] = task
        if let error = await task.value { throw error }
    }

    func isDownloaded(_ id: SpeechModelID) async -> Bool {
        guard let engine = engines[id] else { return false }
        return await engine.isDownloaded()
    }

    /// Nil when the typing model isn't ready or hears nothing.
    func transcribeTyping(_ samples: [Float], hints: [HintTerm]) async -> EngineResult? {
        guard let engine = typingEngine else { return nil }
        do { return try await engine.transcribe(samples, hints: hints) }
        catch { return nil }
    }

    /// Loads the model if it isn't the typing model, runs `body`, then unloads it.
    /// Never downloads: throws `notDownloaded` when the model isn't on disk.
    func withLoaded<T: Sendable>(
        _ id: SpeechModelID,
        _ body: @Sendable (any SpeechEngine) async throws -> T
    ) async throws -> T {
        guard let candidate = engines[id] else { throw ModelLibraryError.unavailable }
        guard await candidate.isDownloaded() else { throw ModelLibraryError.notDownloaded }
        guard let engine = await acquire(id) else {
            await release(id)
            if case .failed(let reason)? = states[id] { throw ModelLibraryError.notReady(reason) }
            throw ModelLibraryError.notReady("The model didn't load.")
        }
        do {
            let result = try await body(engine)
            await release(id)
            return result
        } catch {
            await release(id)
            throw error
        }
    }

    /// Takes a lease and loads the model, returning the engine that loaded. Every acquire needs a matching `release`,
    /// whether or not it loaded.
    private func acquire(_ id: SpeechModelID) async -> (any SpeechEngine)? {
        leases[id, default: 0] += 1
        return await load(id)
    }

    private func release(_ id: SpeechModelID) async {
        let remaining = (leases[id] ?? 1) - 1
        leases[id] = remaining > 0 ? remaining : nil
        await unloadRetiredIfIdle(id)
        await unloadIfIdle(id)
    }

    /// A lease on the replacement also keeps a retired engine, which errs toward letting a job finish.
    private func unloadRetiredIfIdle(_ id: SpeechModelID) async {
        guard leases[id] == nil, let old = retired.removeValue(forKey: id) else { return }
        for engine in old { await engine.unload() }
    }

    /// Unloads a model nothing holds. Registers the teardown before any await, so a later load waits for it.
    private func unloadIfIdle(_ id: SpeechModelID) async {
        guard id != typingModel, leases[id] == nil, let engine = engines[id] else { return }
        if let running = teardowns[id] {
            _ = await running.value
            return
        }
        let task = Task { () -> (any Error)? in
            await engine.unload()
            teardowns[id] = nil
            return nil
        }
        teardowns[id] = task
        _ = await task.value
    }

    /// Waits out an unload or delete, then joins a download or load already running for the same engine.
    /// Returns the model's current engine if it loaded.
    private func load(_ id: SpeechModelID) async -> (any SpeechEngine)? {
        while true {
            while let teardown = teardowns[id] { _ = await teardown.value }
            guard let engine = engines[id] else { return nil }
            let ready: Bool
            if let running = loading[id], running.engine === engine {
                ready = await running.task.value
            } else {
                let task = Task { await run(engine) }
                loading[id] = (engine, task)
                ready = await task.value
                if loading[id]?.engine === engine { loading[id] = nil }
            }
            // A spelling change replaced the engine while it loaded, so load its replacement.
            if engines[id] === engine { return ready ? engine : nil }
        }
    }

    private func run(_ engine: any SpeechEngine) async -> Bool {
        let id = engine.id
        inFlight.insert(id)
        let outcome: ModelState
        if await engine.isLoaded {
            outcome = .ready
        } else {
            let downloaded = await engine.isDownloaded()
            if engines[id] === engine { states[id] = downloaded ? .preparing : .downloading(nil) }
            do {
                try await engine.prepare { [weak self] fraction in
                    Task { @MainActor in self?.noteProgress(engine, fraction) }
                }
                outcome = .ready
            } catch {
                outcome = .failed(String(error.localizedDescription.prefix(200)))
            }
        }
        // If a spelling change replaced this engine, a load of its replacement owns the model's state.
        let current = engines[id] === engine
        if current || loading[id]?.engine === engine { inFlight.remove(id) }
        if current { states[id] = outcome }
        return outcome == .ready
    }

    /// Progress hops arrive in any order, so the state only moves forward.
    private func noteProgress(_ engine: any SpeechEngine, _ fraction: Double?) {
        let id = engine.id
        guard engines[id] === engine, inFlight.contains(id) else { return }
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
}

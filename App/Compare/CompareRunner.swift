import Foundation
import Observation
import SottoCore
import os

/// Runs every downloaded model over the kept clips that don't have its text yet, while the Compare window is open.
///
/// One model at a time: it loads through `withLoaded`, runs over its waiting clips, then unloads before the next.
/// It stops between clips when the window closes, and waits out a dictation with no model loaded.
/// It never downloads. A model that won't load, or a clip it returns nothing for, is skipped until the
/// window opens again, so nothing retries in a loop.
@MainActor
@Observable
final class CompareRunner {
    enum Phase: Equatable {
        case idle
        case running(SpeechModelID)
        case waitingForDictation
        case finished
    }

    private(set) var phase: Phase = .idle
    /// Clip-and-model pairs run since the window opened.
    private(set) var done = 0
    /// Pairs still waiting, counted before each clip.
    private(set) var remaining = 0

    @ObservationIgnored private let library: ModelLibrary
    @ObservationIgnored private let clips: ClipStore
    @ObservationIgnored private let hints: () -> [HintTerm]
    @ObservationIgnored private let isDictating: () -> Bool
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var stopped = true
    /// Clip-and-model pairs that gave no text this session.
    @ObservationIgnored private var skipped: Set<Pair> = []
    /// Models that didn't load this session.
    @ObservationIgnored private var failed: Set<SpeechModelID> = []
    @ObservationIgnored private let log = Logger(subsystem: "app.sotto.desktop", category: "compare")

    private struct Pair: Hashable {
        let clip: UUID
        let model: SpeechModelID
    }

    init(library: ModelLibrary, clips: ClipStore, hints: @escaping () -> [HintTerm],
         isDictating: @escaping () -> Bool) {
        self.library = library
        self.clips = clips
        self.hints = hints
        self.isDictating = isDictating
    }

    /// Starts, or keeps going if already running. Call again when clips or download states change.
    func start() {
        stopped = false
        guard run == nil else { return }
        run = Task {
            await runAll()
            run = nil
        }
    }

    /// Picks up new clips or downloads while the window is open. Does nothing once it's closed.
    func wake() {
        guard !stopped else { return }
        start()
    }

    /// Stops after the current clip and forgets this session's skips.
    func stop() {
        stopped = true
        skipped = []
        failed = []
        done = 0
        if run == nil { phase = .idle }
    }

    private func runAll() async {
        while !stopped {
            if isDictating() {
                phase = .waitingForDictation
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            remaining = pendingCount()
            guard let model = nextModel() else { break }
            phase = .running(model)
            do {
                try await library.withLoaded(model) { [self] engine in
                    while let clip = await nextClip(for: model) {
                        await transcribe(clip, with: engine, model: model)
                    }
                }
            } catch {
                failed.insert(model)
                log.error("compare skipped \(model.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        remaining = pendingCount()
        phase = stopped ? .idle : .finished
    }

    private func transcribe(_ clip: ClipRecord, with engine: any SpeechEngine, model: SpeechModelID) async {
        let pair = Pair(clip: clip.id, model: model)
        guard let samples = await clips.loadSamples(for: clip.id) else {
            skipped.insert(pair)
            return
        }
        let result = try? await engine.transcribe(samples, hints: hints())
        guard let text = result?.hinted, !text.isEmpty else {
            skipped.insert(pair)
            return
        }
        // The clip may have been deleted meanwhile.
        guard var record = clips.records.first(where: { $0.id == clip.id }),
              record.modelTexts[model.rawValue] == nil else { return }
        record.modelTexts[model.rawValue] = text
        clips.update(record)
        done += 1
    }

    /// Nil once the window closed, a dictation started, or the model has no clips left.
    private func nextClip(for model: SpeechModelID) -> ClipRecord? {
        guard !stopped, !isDictating() else { return nil }
        remaining = pendingCount()
        // Newest first, matching the list.
        return clips.records.last { isPending($0, model) }
    }

    /// The typing model first, since it's already loaded, then the catalog's order.
    private func nextModel() -> SpeechModelID? {
        let order = [library.typingModel] + SpeechCatalog.all.map(\.id).filter { $0 != library.typingModel }
        return order.first { model in
            runnable(model) && clips.records.contains { isPending($0, model) }
        }
    }

    private func pendingCount() -> Int {
        let models = SpeechModelID.allCases.filter(runnable)
        return clips.records.reduce(0) { count, record in
            count + models.count { isPending(record, $0) }
        }
    }

    /// Downloaded per the library's states; this never asks the engine, and never downloads.
    private func runnable(_ model: SpeechModelID) -> Bool {
        library.states[model] == .ready && !failed.contains(model)
    }

    private func isPending(_ record: ClipRecord, _ model: SpeechModelID) -> Bool {
        record.compareText(for: model) == nil && !skipped.contains(Pair(clip: record.id, model: model))
    }
}

extension ClipRecord {
    /// The model's version of this clip. The clip's typing model has its text in `rawText`.
    func compareText(for model: SpeechModelID) -> String? {
        if let text = modelTexts[model.rawValue] { return text }
        return model == typingModel && !rawText.isEmpty ? rawText : nil
    }
}

import FluidAudio
import Foundation
import OSLog
import SottoCore

/// Rescores Parakeet text against hint words with FluidAudio's CTC vocabulary boosting, which checks the audio
/// before changing a word. The CTC model is independent of the Parakeet version, so one booster serves every
/// Parakeet engine and a model switch keeps it loaded.
actor HintBooster {
    /// How long a take waits for a session rebuild after the hint list changes.
    private static let rebuildWait = Duration.milliseconds(300)

    private let log = Logger(subsystem: "app.sotto.desktop", category: "dictation")

    private var models: CtcModels?
    private var session: VocabularyBoostingSession?
    /// The hint list `session` was built from.
    private var sessionHints: [HintTerm]?
    /// The hint list the latest take asked for.
    private var wantedHints: [HintTerm] = []
    private var preparation: Task<Void, Never>?
    private var lastFailure: ContinuousClock.Instant?
    /// Takes waiting for a rebuild, resumed when a session is built, preparation ends, or the wait runs out.
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// The rescored text, or `text` unchanged. Never waits for the CTC model download: until it is loaded, takes
    /// come back unchanged. Once it is loaded, a take after a hint list change waits up to `rebuildWait` for the
    /// new session, then comes back unchanged and leaves the rebuild running. Logs the time spent per take.
    func apply(text: String, tokenTimings: [TokenTiming], samples: [Float], hints: [HintTerm]) async -> String {
        let clock = ContinuousClock()
        let start = clock.now
        var waited = Duration.zero
        defer {
            let ms = (clock.now - start) / .milliseconds(1)
            let waitedMS = waited / .milliseconds(1)
            log.debug("hint_booster \(ms, format: .fixed(precision: 1), privacy: .public)ms wait \(waitedMS, format: .fixed(precision: 1), privacy: .public)ms hints \(hints.count, privacy: .public)")
        }

        guard !hints.isEmpty, !tokenTimings.isEmpty else { return text }
        var ready = readySession(for: hints)
        if ready == nil, models != nil {
            let deadline = start + Self.rebuildWait
            // A session built for an older hint list wakes the take early; keep waiting for this list's.
            while ready == nil, preparation != nil, clock.now < deadline {
                await waitForRebuild(until: deadline)
                if let session, sessionHints == hints { ready = session }
            }
            waited = clock.now - start
        }
        guard let session = ready else { return text }
        guard session.hasCTCRescoringCandidates(text: text, tokenTimings: tokenTimings) else { return text }
        guard let output = await session.rescore(text: text, tokenTimings: tokenTimings, audioSamples: samples),
              output.wasModified
        else { return text }
        let rescored = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return rescored.isEmpty ? text : rescored
    }

    /// The session for `hints`, or nil while one is being prepared. Starts the download or rebuild if needed.
    private func readySession(for hints: [HintTerm]) -> VocabularyBoostingSession? {
        if let session, sessionHints == hints { return session }
        wantedHints = hints
        if preparation == nil, lastFailure.map({ $0.duration(to: .now) > .seconds(60) }) ?? true {
            preparation = Task { await prepare() }
        }
        return nil
    }

    /// Returns when the next session is built, preparation ends, or `deadline` passes, whichever is first.
    /// The rebuild itself keeps running.
    private func waitForRebuild(until deadline: ContinuousClock.Instant) async {
        let id = UUID()
        await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(until: deadline, clock: .continuous)
                await self?.resumeWaiter(id)
            }
        }
    }

    private func resumeWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }

    private func resumeAllWaiters() {
        let pending = waiters
        waiters = [:]
        for continuation in pending.values { continuation.resume() }
    }

    /// Downloads the CTC model the first time, then builds sessions until one matches the latest hint list.
    private func prepare() async {
        defer {
            preparation = nil
            resumeAllWaiters()
        }
        do {
            if models == nil {
                models = try await CtcModels.downloadAndLoad(to: nil, variant: .ctc110m)
            }
            while let models, sessionHints != wantedHints {
                let hints = wantedHints
                let terms = hints.map { CustomVocabularyTerm(text: $0.text, aliases: $0.aliases) }
                session = try await VocabularyBoostingSession(
                    vocabulary: CustomVocabularyContext(terms: terms), ctcModels: models)
                sessionHints = hints
                resumeAllWaiters()
            }
            lastFailure = nil
        } catch {
            lastFailure = .now
            log.error("hint booster unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}

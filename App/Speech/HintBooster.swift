import FluidAudio
import Foundation
import OSLog
import SottoCore

/// Rescores Parakeet text against hint words with FluidAudio's CTC vocabulary boosting, which checks the audio
/// before changing a word. The CTC model is independent of the Parakeet version, so one booster serves every
/// Parakeet engine and a model switch keeps it loaded.
actor HintBooster {
    private let log = Logger(subsystem: "app.sotto.desktop", category: "dictation")

    private var models: CtcModels?
    private var session: VocabularyBoostingSession?
    /// The hint list `session` was built from.
    private var sessionHints: [HintTerm]?
    /// The hint list the latest take asked for.
    private var wantedHints: [HintTerm] = []
    private var preparation: Task<Void, Never>?
    private var lastFailure: ContinuousClock.Instant?

    /// The rescored text, or `text` unchanged. Never waits for the CTC model: until it has downloaded and the
    /// session matches `hints`, takes come back unchanged while that happens in the background.
    func apply(text: String, tokenTimings: [TokenTiming], samples: [Float], hints: [HintTerm]) async -> String {
        guard !hints.isEmpty, !tokenTimings.isEmpty, let session = readySession(for: hints) else { return text }
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

    /// Downloads the CTC model the first time, then builds sessions until one matches the latest hint list.
    private func prepare() async {
        defer { preparation = nil }
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
            }
            lastFailure = nil
        } catch {
            lastFailure = .now
            log.error("hint booster unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}

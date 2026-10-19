import Foundation
import IOKit.ps
import SottoCore
import os

/// Rechecks kept clips with the slower teacher model while the Mac is idle and on mains power,
/// and reports each phrase the typing model heard differently.
///
/// A clip the teacher returns nothing for (too short, silent, or Cohere's output was token-capped) is saved
/// with an empty teacher text, so it isn't tried again. A clip whose audio can't be read or whose
/// transcription throws is skipped until the next launch.
@MainActor
final class TeacherScheduler {
    private let library: ModelLibrary
    private let clips: ClipStore
    private let settings: () -> AppSettings
    private let onSubstitution: (Substitution, UUID) -> Void
    private var timer: Timer?
    private var run: Task<Void, Never>?
    private var lastDictation = Date()
    private var skipped: Set<UUID> = []
    private let log = Logger(subsystem: "app.sotto.desktop", category: "teacher")

    init(library: ModelLibrary, clips: ClipStore, settings: @escaping () -> AppSettings,
         onSubstitution: @escaping (Substitution, UUID) -> Void) {
        self.library = library
        self.clips = clips
        self.settings = settings
        self.onSubstitution = onSubstitution
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A running teacher stops after its current clip.
    func noteDictation() {
        lastDictation = Date()
    }

    private func check() {
        guard run == nil, let teacher = settings().teacherModel, mayContinue(with: teacher) else { return }
        run = Task {
            await teach(with: teacher)
            run = nil
        }
    }

    /// Everything but the download check, which is async. Also checked between clips.
    private func mayContinue(with teacher: SpeechModelID) -> Bool {
        settings().teacherModel == teacher
            && TeacherQueue.isIdle(lastDictation: lastDictation, now: Date())
            && !TeacherQueue.pending(clips.records, teacher: teacher, skipping: skipped).isEmpty
            && Self.onMainsPower()
    }

    private func teach(with teacher: SpeechModelID) async {
        guard await library.isDownloaded(teacher) else { return }
        do {
            let checked = try await library.withLoaded(teacher) { [self] engine in
                var count = 0
                while let clip = await nextClip(for: teacher) {
                    guard let samples = await clips.loadSamples(for: clip.id) else {
                        await skip(clip.id)
                        continue
                    }
                    let result: EngineResult?
                    do {
                        result = try await engine.transcribe(samples, hints: [])
                    } catch {
                        await skip(clip.id)
                        continue
                    }
                    let text = result?.raw ?? ""
                    let found = text.isEmpty ? [] : TeacherQueue.substitutions(in: clip, teacherText: text)
                    await save(text, found: found, for: clip.id, teacher: teacher)
                    count += 1
                }
                return count
            }
            log.info("teacher checked \(checked, privacy: .public) clip(s)")
        } catch {
            log.error("teacher didn't run: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Nil once a dictation started, the power was unplugged, the teacher changed, or no clips are left.
    private func nextClip(for teacher: SpeechModelID) -> ClipRecord? {
        guard mayContinue(with: teacher) else { return nil }
        return TeacherQueue.pending(clips.records, teacher: teacher, skipping: skipped).first
    }

    private func skip(_ id: UUID) {
        skipped.insert(id)
    }

    /// Skips a clip deleted, or checked by Compare, while the teacher listened.
    private func save(_ text: String, found: [Substitution], for id: UUID, teacher: SpeechModelID) {
        guard var record = clips.records.first(where: { $0.id == id }), record.teacherText == nil else { return }
        record.teacherModel = teacher
        record.teacherText = text
        clips.update(record)
        for substitution in found {
            onSubstitution(substitution, id)
        }
    }

    /// A Mac without a battery reports AC power. If the power state can't be read, it counts as mains.
    private static func onMainsPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (type as String) == kIOPMACPowerKey
    }
}

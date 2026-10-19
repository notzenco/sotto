import Foundation
import SottoCore

/// The owner's picks and corrections in the Compare window.
///
/// Each choice is saved on the clip at once, so the list and score show it. Learning waits for `flush`, when the
/// window closes or Sotto quits, and then learns once per clip from its final choice, so a misclick that's
/// changed or cleared teaches nothing.
@MainActor
final class ComparePicks {
    private weak var model: AppModel?
    /// Clips chosen since the last flush.
    private var pending: Set<UUID> = []

    init(model: AppModel) {
        self.model = model
    }

    /// Picks the model's version, or clears the pick if it's already picked.
    func pick(_ id: SpeechModelID, clip: UUID) {
        guard var record = record(clip) else { return }
        if record.pickedModel == id {
            record.pickedModel = nil
        } else {
            guard record.compareText(for: id) != nil else { return }
            record.pickedModel = id
            record.correctedText = nil
        }
        save(record)
    }

    /// Saves the owner's text in place of a pick. Empty text clears the correction.
    func correct(_ typed: String, clip: UUID) {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var record = record(clip), record.correctedText != (text.isEmpty ? nil : text) else { return }
        if text.isEmpty {
            record.correctedText = nil
        } else {
            record.correctedText = text
            record.pickedModel = nil
        }
        save(record)
    }

    /// Learns each phrase the typing model heard differently from each chosen clip's final choice.
    func flush() {
        guard let model else { return }
        let clips = pending
        pending = []
        for id in clips {
            guard let record = record(id),
                  let chosen = record.pickedModel.flatMap(record.compareText(for:)) ?? record.correctedText
            else { continue }
            for substitution in PhraseAligner.learningSubstitutions(from: record.rawText, to: chosen) {
                model.recordLearning(substitution, source: .compare, clipID: id)
            }
        }
    }

    private func record(_ id: UUID) -> ClipRecord? {
        model?.clips.records.first { $0.id == id }
    }

    private func save(_ record: ClipRecord) {
        var record = record
        // So the typing model is scored like the others, on what the owner got.
        if record.modelTexts[record.typingModel.rawValue] == nil, !record.hintedText.isEmpty {
            record.modelTexts[record.typingModel.rawValue] = record.hintedText
        }
        model?.clips.update(record)
        if record.pickedModel != nil || record.correctedText != nil {
            pending.insert(record.id)
        } else {
            pending.remove(record.id)
        }
    }
}

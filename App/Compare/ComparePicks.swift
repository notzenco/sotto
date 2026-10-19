import Foundation
import SottoCore

/// The owner's picks and corrections in the Compare window.
///
/// Each choice is saved on the clip at once, so the list and score show it. Learning waits for `flush`, when the
/// window closes or Sotto quits, and then learns once per clip from its final choice, so a misclick that's
/// changed or cleared teaches nothing. A word the owner deletes after choosing isn't learned back at close.
@MainActor
final class ComparePicks {
    private weak var model: AppModel?
    /// Clips chosen since the last flush, with the lexicon as it was at the latest choice.
    private var pending: [UUID: Lexicon] = [:]

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
        pending = [:]
        for (id, lexiconAtChoice) in clips {
            guard let record = record(id),
                  let chosen = record.pickedModel.flatMap(record.compareText(for:)) ?? record.correctedText
            else { continue }
            for substitution in PhraseAligner.learningSubstitutions(from: record.rawText, to: chosen) {
                // Deleted since the choice: the deletion is newer, so it stands. A word already deleted when the
                // owner chose it is learned again, as a Compare pick unblocks it.
                if model.lexicon.blocks(substitution.written), !lexiconAtChoice.blocks(substitution.written) {
                    continue
                }
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
        guard let model else { return }
        model.clips.update(record)
        if record.pickedModel != nil || record.correctedText != nil {
            pending[record.id] = model.lexicon
        } else {
            pending[record.id] = nil
        }
    }
}

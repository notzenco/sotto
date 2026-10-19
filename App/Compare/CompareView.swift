import AppKit
import SottoCore
import SwiftUI

/// Kept clips newest first, each with every downloaded model's version. Clicking a version, or typing the right
/// text, saves the pick, keeps score and teaches Sotto the words the typing model got wrong.
struct CompareView: View {
    var model: AppModel
    var runner: CompareRunner
    var player: ClipPlayer
    /// Rebuilt only when the clips or download states change, never on a progress tick.
    @State private var rows: [CompareRow] = []
    @State private var scores: [CompareScoreItem] = []

    var body: some View {
        VStack(spacing: 0) {
            CompareHeader(runner: runner, scores: scores)
            Divider()
            if rows.isEmpty {
                ContentUnavailableView(
                    "No kept clips",
                    systemImage: "waveform",
                    description: Text("Dictations are kept here for 7 days while Keep audio is on.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(rows) { row in
                            ClipCard(
                                row: row,
                                isPlaying: player.playing == row.id,
                                play: { player.toggle(row.id, clips: model.clips) },
                                pick: { pick($0, clip: row.id) },
                                correct: { correct($0, clip: row.id) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 400)
        .onAppear(perform: rebuild)
        .onChange(of: model.clips.records) {
            rebuild()
            runner.wake()
        }
        .onChange(of: model.library.states) {
            rebuild()
            runner.wake()
        }
    }

    private func rebuild() {
        let records = model.clips.records
        let downloaded = Set(SpeechModelID.allCases.filter { model.library.states[$0] == .ready })
        rows = records.sorted { $0.date > $1.date }.map { CompareRow($0, downloaded: downloaded) }
        let tally = CompareScore.tally(records)
        scores = SpeechCatalog.all.compactMap { info in
            let score = tally[info.id]
            guard score != nil || downloaded.contains(info.id) else { return nil }
            return CompareScoreItem(id: info.id, name: info.name,
                                    right: score?.right ?? 0, judged: score?.judged ?? 0)
        }
    }

    private func pick(_ id: SpeechModelID, clip: UUID) {
        guard var record = model.clips.records.first(where: { $0.id == clip }), record.pickedModel != id,
              let text = record.compareText(for: id) else { return }
        record.pickedModel = id
        record.correctedText = nil
        save(record, chosen: text)
    }

    private func correct(_ typed: String, clip: UUID) {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var record = model.clips.records.first(where: { $0.id == clip }),
              record.correctedText != text else { return }
        record.correctedText = text
        record.pickedModel = nil
        save(record, chosen: text)
    }

    /// Learns each phrase the typing model heard differently from the chosen text.
    private func save(_ record: ClipRecord, chosen: String) {
        var record = record
        // So the typing model is scored like the others.
        if record.modelTexts[record.typingModel.rawValue] == nil, !record.rawText.isEmpty {
            record.modelTexts[record.typingModel.rawValue] = record.rawText
        }
        model.clips.update(record)
        for substitution in PhraseAligner.substitutions(from: record.rawText, to: chosen) {
            model.recordLearning(substitution, source: .compare, clipID: record.id)
        }
    }
}

struct CompareRow: Identifiable, Equatable {
    struct Version: Identifiable, Equatable {
        let id: SpeechModelID
        let name: String
        /// Nil while the model hasn't run on this clip.
        let text: String?
        let picked: Bool
    }

    let id: UUID
    let date: Date
    let app: String
    let length: String
    let versions: [Version]
    let correctedText: String?

    /// Every downloaded model, plus any model that has a version of this clip, in the catalog's order.
    @MainActor
    init(_ record: ClipRecord, downloaded: Set<SpeechModelID>) {
        id = record.id
        date = record.date
        app = record.bundleID.map(AppNames.name(for:)) ?? ""
        length = Duration.seconds(record.durationSeconds).formatted(.time(pattern: .minuteSecond))
        versions = SpeechCatalog.all.compactMap { info in
            let text = record.compareText(for: info.id)
            guard text != nil || downloaded.contains(info.id) else { return nil }
            return Version(id: info.id, name: info.name, text: text, picked: record.pickedModel == info.id)
        }
        correctedText = record.correctedText
    }
}

struct CompareScoreItem: Identifiable, Equatable {
    let id: SpeechModelID
    let name: String
    let right: Int
    let judged: Int
}

/// App names by bundle ID, looked up once each.
@MainActor
private enum AppNames {
    private static var cache: [String: String] = [:]

    static func name(for bundleID: String) -> String {
        if let name = cache[bundleID] { return name }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
        cache[bundleID] = name
        return name
    }
}

private struct CompareHeader: View {
    var runner: CompareRunner
    let scores: [CompareScoreItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            progress
            if !scores.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(scores) { score in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(score.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(score.right) / \(score.judged)")
                                .font(.title3.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(score.name): \(score.right) right of \(score.judged) judged")
                    }
                }
            }
            Text("Click the version that matches what you said.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var progress: some View {
        switch runner.phase {
        case .running(let id):
            VStack(alignment: .leading, spacing: 4) {
                Text("Running \(SpeechCatalog.info(id).name)… \(runner.remaining) left")
                ProgressView(value: Double(runner.done), total: Double(max(runner.done + runner.remaining, 1)))
            }
        case .waitingForDictation:
            Text("Paused while you dictate.")
                .foregroundStyle(.secondary)
        case .idle, .finished:
            Text("Nothing left to run.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClipCard: View {
    let row: CompareRow
    let isPlaying: Bool
    let play: () -> Void
    let pick: (SpeechModelID) -> Void
    let correct: (String) -> Void
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: play) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                .help(isPlaying ? "Stop" : "Play")
                .accessibilityLabel(isPlaying ? "Stop" : "Play")
                Text(row.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                if !row.app.isEmpty {
                    Text(row.app).foregroundStyle(.secondary)
                }
                Spacer()
                Text(row.length)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ForEach(row.versions) { version in
                Button { pick(version.id) } label: {
                    choice(title: version.name, text: version.text ?? "Waiting to run…",
                           chosen: version.picked, waiting: version.text == nil)
                }
                .buttonStyle(.plain)
                .disabled(version.text == nil)
            }
            if editing {
                HStack {
                    TextField("What you said", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { editing = false }
                }
            } else {
                if let corrected = row.correctedText {
                    choice(title: "Your text", text: corrected, chosen: true, waiting: false)
                }
                Button(row.correctedText == nil ? "None of these…" : "Edit your text…") {
                    draft = row.correctedText ?? row.versions.compactMap(\.text).first ?? ""
                    editing = true
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func choice(title: String, text: String, chosen: Bool, waiting: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .foregroundStyle(waiting ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        correct(text)
        editing = false
    }
}

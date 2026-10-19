import AppKit
import KeyboardShortcuts
import ServiceManagement
import SottoCore
import SwiftUI

struct GeneralSettingsPane: View {
    var model: AppModel
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Sotto at login", isOn: Binding(
                    get: { model.openAtLogin },
                    set: { loginError = model.setOpenAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.loginRequiresApproval {
                    Text("Approve Sotto in System Settings → General → Login Items")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Login Items") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLoginItem() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginItem()
        }
    }
}

struct PrivacySettingsPane: View {
    var model: AppModel

    var body: some View {
        Form {
            Section {
                permissionRow("Microphone", allowed: model.microphoneOn) {
                    model.requestMicrophoneAccess()
                }
                permissionRow("Accessibility", allowed: model.accessibilityOn) {
                    model.requestAccessibility()
                }
            }
            Section {
                Text(model.settings.keepAudio
                     ? "Audio of each dictation is kept on this Mac for 7 days to improve recognition, and is never sent anywhere. Nothing leaves this Mac except model downloads."
                     : "Audio is never saved, and nothing leaves this Mac except model downloads.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }

    private func permissionRow(_ title: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if allowed {
                Text("Allowed").foregroundStyle(.green)
            } else {
                Button("Turn On", action: action)
                    .accessibilityLabel("Turn On \(title)")
            }
        }
    }
}

struct ShortcutSettingsPane: View {
    var model: AppModel

    var body: some View {
        Form {
            Section {
                Text("Hold Right Command. Double-tap to leave it on. Esc cancels. Or record a chord.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.accessibilityOn {
                    Text("Turn on Accessibility so macOS will deliver Right Command.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Turn on Accessibility") { model.requestAccessibility() }
                }
                KeyboardShortcuts.Recorder("Chord", name: .pushToTalk)
            }
        }
        .formStyle(.grouped)
    }
}

struct MicrophoneSettingsPane: View {
    var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: microphoneSelection) {
                    Text("System Default").tag(UInt32?.none)
                    ForEach(model.microphones) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                ProgressView(value: model.engineRunning ? Double(model.inputLevel) : 0, total: 1) {
                    Text("Input level")
                }
                .progressViewStyle(.linear)
                if !model.engineRunning {
                    Text("Shows while the microphone is open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Keep the first syllable", isOn: syllableSelection)
                Text("A short buffer stays in memory and is overwritten. Audio is not written to disk.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshMicrophones()
        }
    }

    private var microphoneSelection: Binding<UInt32?> {
        Binding(
            get: { model.settings.inputDeviceID },
            set: { model.selectMicrophone($0) }
        )
    }

    private var syllableSelection: Binding<Bool> {
        Binding(
            get: { model.settings.keepFirstSyllable },
            set: { model.setKeepFirstSyllable($0) }
        )
    }
}

struct SpeechSettingsPane: View {
    var model: AppModel
    @State private var modelToDelete: SpeechModelID?
    @State private var deleteError: String?
    @State private var confirmingKeepAudioOff = false
    @State private var confirmingDeleteClips = false

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: modeSelection) {
                    Text("Automatic").tag(Optional<DictationMode>.none)
                    Text(DictationMode.prose.label).tag(Optional(DictationMode.prose))
                    Text(DictationMode.literal.label).tag(Optional(DictationMode.literal))
                }
                .pickerStyle(.segmented)
            }
            Section("Typing model") {
                ForEach(SpeechCatalog.all, id: \.id) { info in
                    typingModelRow(info)
                }
                if let deleteError {
                    Text(deleteError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Teacher") {
                Picker("Teacher", selection: teacherSelection) {
                    Text("Off").tag(SpeechModelID?.none)
                    ForEach(teacherChoices, id: \.id) { info in
                        Text(name(of: info)).tag(Optional(info.id))
                    }
                }
                .pickerStyle(.menu)
                if let teacher = model.settings.teacherModel {
                    teacherStatus(SpeechCatalog.info(teacher))
                } else {
                    Text("Learning from your fixes and from Compare still works without a teacher.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Picker("Spelling", selection: spellingSelection) {
                    ForEach(SpellingVariety.allCases, id: \.self) { variety in
                        Text(variety.label).tag(variety)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Compare models") {
                Toggle("Keep audio for comparing models", isOn: keepAudioSelection)
                Text("Clips stay on this Mac for 7 days.")
                    .foregroundStyle(.secondary)
                LabeledContent("Kept clips") {
                    HStack {
                        Text(clipCountText)
                        Button("Delete All…") { confirmingDeleteClips = true }
                            .disabled(model.clips.records.isEmpty)
                    }
                }
                LabeledContent("See each model's version of your clips and pick the right one") {
                    Button("Compare…") { model.openCompare() }
                        .disabled(model.clips.records.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.library.refreshDownloadStates() }
        // A stale error such as "busy" goes once any model's state moves on.
        .onChange(of: model.library.states) { deleteError = nil }
        .confirmationDialog(
            modelToDelete.map { "Delete \(name(of: SpeechCatalog.info($0)))?" } ?? "",
            isPresented: Binding(get: { modelToDelete != nil }, set: { if !$0 { modelToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let id = modelToDelete { delete(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can download it again later.")
        }
        .confirmationDialog(
            "Delete the \(clipCountText)?",
            isPresented: $confirmingKeepAudioOff
        ) {
            Button("Delete", role: .destructive) { model.setKeepAudio(false, deleteExisting: true) }
            Button("Keep") { model.setKeepAudio(false, deleteExisting: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New dictations won't be kept either way. Kept clips are deleted after 7 days.")
        }
        .confirmationDialog(
            "Delete all \(clipCountText)?",
            isPresented: $confirmingDeleteClips
        ) {
            Button("Delete", role: .destructive) { model.deleteAllClips() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func typingModelRow(_ info: SpeechModelInfo) -> some View {
        let state = model.library.states[info.id]
        let inUse = model.library.typingModel == info.id
        // A model being switched to shows as chosen while it downloads or prepares; typing stays on the old one.
        let chosen = (model.library.pendingSelection ?? model.library.typingModel) == info.id
        return HStack(alignment: .center, spacing: 10) {
            Button {
                guard !chosen else { return }
                deleteError = nil
                model.setTypingModel(info.id)
            } label: {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Type with \(name(of: info))")
            .accessibilityAddTraits(chosen ? .isSelected : [])
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name(of: info))
                    Text(sizeText(info))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(info.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !info.acceptsHints {
                    Text("No hint words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if case .failed(let reason)? = state {
                    Text(reason.isEmpty ? "Failed" : reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            switch state {
            case .downloading(let fraction)?:
                progress(fraction)
            case .preparing?:
                Text("Preparing…").foregroundStyle(.secondary)
            case .failed?:
                Button("Retry") {
                    if inUse {
                        model.retryModel()
                    } else if chosen {
                        model.setTypingModel(info.id)
                    } else {
                        download(info.id)
                    }
                }
            case .ready?:
                if inUse {
                    Text("In use").foregroundStyle(.secondary)
                } else if info.kind == .apple {
                    // Built into macOS, so there is nothing to delete.
                    Text("Built in").foregroundStyle(.secondary)
                } else {
                    Text("Downloaded").foregroundStyle(.secondary)
                    if !chosen {
                        Button("Delete…") { modelToDelete = info.id }
                            .accessibilityLabel("Delete \(name(of: info))")
                    }
                }
            case .notDownloaded?:
                Button("Download") { download(info.id) }
                    .accessibilityLabel("Download \(name(of: info))")
            case nil:
                if inUse {
                    Text("In use").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The teacher row never starts a download itself; only its Download button does.
    @ViewBuilder
    private func teacherStatus(_ info: SpeechModelInfo) -> some View {
        if info.id == model.settings.typingModel {
            Text("The teacher has to be a different model from the typing model.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            switch model.library.states[info.id] {
            case .notDownloaded?, .failed?:
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(downloadPrompt(info))
                            .fixedSize(horizontal: false, vertical: true)
                        if case .failed(let reason)? = model.library.states[info.id], !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Button("Download") { download(info.id) }
                }
            case .downloading(let fraction)?:
                LabeledContent("Downloading \(name(of: info))") { progress(fraction) }
            case .preparing?:
                LabeledContent(name(of: info)) { Text("Preparing…").foregroundStyle(.secondary) }
            case .ready?, nil:
                EmptyView()
            }
        }
    }

    private func progress(_ fraction: Double?) -> some View {
        Group {
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .frame(width: 90)
    }

    private var teacherChoices: [SpeechModelInfo] {
        let teacher = model.settings.teacherModel
        // Keeps a teacher that equals the typing model listed, so the picker still shows it.
        return SpeechCatalog.all.filter { $0.id != model.settings.typingModel || $0.id == teacher }
    }

    private func downloadPrompt(_ info: SpeechModelInfo) -> String {
        let size = info.approximateMegabytes.map { " (\(Self.formatSize(megabytes: $0)))" } ?? ""
        return "Download \(name(of: info))\(size) to start background learning"
    }

    /// Apple's model shows the English it listens for, which follows the spelling setting.
    private func name(of info: SpeechModelInfo) -> String {
        info.id == .appleEnglish ? "\(info.name) (\(model.settings.spelling.label))" : info.name
    }

    private func sizeText(_ info: SpeechModelInfo) -> String {
        info.approximateMegabytes.map { Self.formatSize(megabytes: $0) } ?? "Built in"
    }

    private static func formatSize(megabytes: Int) -> String {
        megabytes >= 1000
            ? "\((Double(megabytes) / 1000).formatted(.number.precision(.fractionLength(0...1)))) GB"
            : "\(megabytes) MB"
    }

    private var clipCountText: String {
        let count = model.clips.records.count
        return count == 1 ? "1 kept clip" : "\(count) kept clips"
    }

    private func download(_ id: SpeechModelID) {
        deleteError = nil
        Task { await model.library.download(id) }
    }

    private func delete(_ id: SpeechModelID) {
        deleteError = nil
        Task {
            do { try await model.library.delete(id) }
            catch { deleteError = error.localizedDescription }
        }
    }

    private var modeSelection: Binding<DictationMode?> {
        Binding(
            get: { model.settings.modeOverride },
            set: { model.setModeOverride($0) }
        )
    }

    private var teacherSelection: Binding<SpeechModelID?> {
        Binding(
            get: { model.settings.teacherModel },
            set: { model.setTeacherModel($0) }
        )
    }

    private var spellingSelection: Binding<SpellingVariety> {
        Binding(
            get: { model.settings.spelling },
            set: {
                model.setSpelling($0)
                // Changing spelling rebuilds Apple's engine and clears its state, so look it up again.
                model.library.refreshDownloadStates()
            }
        )
    }

    /// Turning it off asks about the clips already kept, if there are any.
    private var keepAudioSelection: Binding<Bool> {
        Binding(
            get: { model.settings.keepAudio },
            set: { on in
                if on || model.clips.records.isEmpty {
                    model.setKeepAudio(on, deleteExisting: false)
                } else {
                    confirmingKeepAudioOff = true
                }
            }
        )
    }
}

struct DictionarySettingsPane: View {
    var model: AppModel
    @State private var heard = ""
    @State private var written = ""
    @State private var yourWord = ""

    var body: some View {
        Form {
            Section("Learned") {
                if model.lexicon.learnedWords.isEmpty {
                    Text("Words Sotto learns from your fixes, from Compare and from the teacher show here.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.lexicon.learnedWords) { word in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.written)
                            if !word.heardForms.isEmpty {
                                Text("Heard as \(word.heardForms.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(origin(of: word))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // No confirmation: the word stays blocked and can be added again under Your words.
                        Button("Delete") { model.deleteLearnedWord(id: word.id) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(word.written)")
                    }
                }
            }
            Section("Your words") {
                if model.lexicon.yourWords.isEmpty {
                    Text("Slang, names and brands you want Sotto to listen for.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.lexicon.yourWords, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button("Delete") { model.removeYourWord(word) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(word)")
                    }
                }
                HStack {
                    TextField("Word", text: $yourWord)
                        .onSubmit(addYourWord)
                    Button("Add", action: addYourWord)
                        .disabled(yourWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Names") {
                if model.rulebook.replacements.isEmpty {
                    Text("When a name comes out wrong, write the spelling here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.rulebook.replacements) { row in
                    HStack {
                        Text(row.heard)
                        Text("→").foregroundStyle(.secondary)
                        Text(row.written)
                        Spacer()
                        Button("Delete") { model.deleteReplacement(id: row.id) }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("When you say", text: $heard)
                    TextField("Write", text: $written)
                    Button("Add") {
                        model.addReplacement(heard: heard, written: written)
                        heard = ""
                        written = ""
                    }
                    .disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty
                        || written.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addYourWord() {
        guard !yourWord.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.addYourWord(yourWord)
        yourWord = ""
    }

    private func origin(of word: LearnedWord) -> String {
        let sources = word.sources.map { source in
            switch source {
            case .fix: "your fix"
            case .compare: "Compare"
            case .teacher: "the teacher"
            }
        }
        let from = sources.isEmpty ? "" : "From \(sources.formatted(.list(type: .and))) · "
        let times = word.count == 1 ? "once" : "\(word.count) times"
        return from + times
    }
}

struct HistorySettingsPane: View {
    var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("History", selection: historySelection) {
                    Text("Off").tag(0)
                    Text("24 hours").tag(24)
                }
                .pickerStyle(.segmented)
            }
            Section {
                if model.settings.historyHours == 0 {
                    Text("History is off").foregroundStyle(.secondary)
                } else if model.history.isEmpty {
                    Text("No dictations in the last 24 hours").foregroundStyle(.secondary)
                } else {
                    ForEach(model.history.sorted { $0.date > $1.date }) { entry in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    if let bundleID = entry.bundleID {
                                        Text(appName(for: bundleID))
                                    }
                                    Text(entry.date, style: .time)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Copy") { model.copy(entry.text) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var historySelection: Binding<Int> {
        Binding(
            get: { model.settings.historyHours },
            set: { model.setHistoryHours($0) }
        )
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}

struct AboutSettingsPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Form {
            Section {
                Text("Sotto \(version)")
                    .font(.headline)
            }
            Section("Credits") {
                ForEach(SpeechCatalog.all.filter { !$0.credit.isEmpty }, id: \.id) { info in
                    Text(info.credit)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let credit = SpellingConverter.credit {
                    Text(credit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                DisclosureGroup("Spelling list licence") {
                    Text(SpellingConverter.licenceNotice)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }
}

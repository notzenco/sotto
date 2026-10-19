import KeyboardShortcuts
import SwiftUI
import SottoCore

struct SettingsView: View {
    var model: AppModel
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Shortcut") {
                    Text("Hold Right Command. Double-tap to leave it on. Esc cancels. Or record a chord.")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: Palette.graphite))
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.accessibilityOn {
                        Text("Turn on Accessibility so macOS will deliver Right Command.")
                            .font(.callout)
                            .foregroundStyle(Color(nsColor: Palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Turn on Accessibility") { model.requestAccessibility() }
                    }
                    KeyboardShortcuts.Recorder("Chord", name: .pushToTalk)
                }
                section("Microphone") {
                    Picker("Microphone", selection: microphoneSelection) {
                        Text("System Default").tag(UInt32?.none)
                        ForEach(model.microphones) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                section("Language") {
                    Text("English")
                        .foregroundStyle(Color(nsColor: Palette.ink))
                }
                section("Names") {
                    if model.rulebook.replacements.isEmpty {
                        Text("When a name comes out wrong, write the spelling here.")
                            .font(.callout)
                            .foregroundStyle(Color(nsColor: Palette.graphite))
                    }
                    ForEach(model.rulebook.replacements) { row in
                        HStack {
                            Text(row.heard)
                            Text("→")
                                .foregroundStyle(Color(nsColor: Palette.graphite))
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
                section("Privacy") {
                    Picker("History", selection: historySelection) {
                        Text("Off").tag(0)
                        Text("24 hours").tag(24)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Keep the first syllable", isOn: syllableSelection)
                    Text("A short buffer stays in memory and is overwritten. Audio is not written to disk.")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: Palette.graphite))
                        .fixedSize(horizontal: false, vertical: true)
                }
                section("Mode") {
                    Picker("Mode", selection: modeSelection) {
                        Text("Automatic").tag(Optional<DictationMode>.none)
                        Text(DictationMode.prose.label).tag(Optional(DictationMode.prose))
                        Text(DictationMode.literal.label).tag(Optional(DictationMode.literal))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                section("Speech model") {
                    Text(model.modelStatusLine)
                        .foregroundStyle(Color(nsColor: Palette.ink))
                    if case .failed = model.modelPhase {
                        Button("Retry") { model.retryModel() }
                    }
                }
                Text("Speech model: NVIDIA Parakeet TDT 0.6B v2, via FluidAudio. Weights are CC-BY-4.0.")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: Palette.graphite))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: Palette.paper))
        .onAppear { model.refreshMicrophones() }
    }

    private var microphoneSelection: Binding<UInt32?> {
        Binding(
            get: { model.settings.inputDeviceID },
            set: { model.selectMicrophone($0) }
        )
    }

    private var historySelection: Binding<Int> {
        Binding(
            get: { model.settings.historyHours },
            set: { model.setHistoryHours($0) }
        )
    }

    private var syllableSelection: Binding<Bool> {
        Binding(
            get: { model.settings.keepFirstSyllable },
            set: { model.setKeepFirstSyllable($0) }
        )
    }

    private var modeSelection: Binding<DictationMode?> {
        Binding(
            get: { model.settings.modeOverride },
            set: { model.setModeOverride($0) }
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(nsColor: Palette.ink))
            content()
        }
    }
}

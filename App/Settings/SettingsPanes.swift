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
                Text("Audio is never saved, and nothing leaves this Mac except the speech model download.")
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
            model.setLevelWatching(true, for: .meter)
        }
        .onDisappear { model.setLevelWatching(false, for: .meter) }
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
            Section("Speech model") {
                Text(model.modelStatusLine)
                if case .failed = model.modelPhase {
                    Button("Retry") { model.retryModel() }
                }
            }
            Section {
                Text("Language: English")
            }
        }
        .formStyle(.grouped)
    }

    private var modeSelection: Binding<DictationMode?> {
        Binding(
            get: { model.settings.modeOverride },
            set: { model.setModeOverride($0) }
        )
    }
}

struct DictionarySettingsPane: View {
    var model: AppModel
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        Form {
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
                Text("Speech model: NVIDIA Parakeet TDT 0.6B v2 (CC-BY-4.0), via FluidAudio.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

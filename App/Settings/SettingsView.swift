import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcut, indicator, microphone, speech, dictionary, history, privacy, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcut: "Shortcut"
        case .indicator: "Indicator"
        case .microphone: "Microphone"
        case .speech: "Speech"
        case .dictionary: "Dictionary"
        case .history: "History"
        case .privacy: "Privacy & Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcut: "command"
        case .indicator: "waveform"
        case .microphone: "mic.fill"
        case .speech: "textformat"
        case .dictionary: "book.closed.fill"
        case .history: "clock.arrow.circlepath"
        case .privacy: "lock.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .shortcut: .blue
        case .indicator: .pink
        case .microphone: .orange
        case .speech: .green
        case .dictionary: .purple
        case .history: .brown
        case .privacy: .gray
        case .about: .gray
        }
    }
}

struct SettingsView: View {
    var model: AppModel
    @AppStorage("settingsPane") private var selectedPane: SettingsPane = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsPane.allCases, selection: selection) { pane in
                HStack(spacing: 8) {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(pane.tint, in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityHidden(true)
                    Text(pane.title)
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            detail
                .navigationTitle(selectedPane.title)
        }
    }

    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { selectedPane },
            set: { if let pane = $0 { selectedPane = pane } }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsPane(model: model)
        case .privacy:
            PrivacySettingsPane(model: model)
        case .shortcut:
            ShortcutSettingsPane(model: model)
        case .indicator:
            Form {
                Text("Indicator settings arrive in the next step")
            }
            .formStyle(.grouped)
        case .microphone:
            MicrophoneSettingsPane(model: model)
        case .speech:
            SpeechSettingsPane(model: model)
        case .dictionary:
            DictionarySettingsPane(model: model)
        case .history:
            HistorySettingsPane(model: model)
        case .about:
            AboutSettingsPane()
        }
    }
}

import Foundation
import SottoCore

struct AppSettings: Codable, Equatable, Sendable {
    var keepFirstSyllable: Bool = true
    /// Zero means history is off. Twenty-four keeps text for a day on this Mac.
    var historyHours: Int = 0
    /// Nil follows the focused app. A value forces Prose or Literal.
    var modeOverride: DictationMode? = nil
    var inputDeviceID: UInt32? = nil
    var dictationCount: Int = 0

    var automaticMode: Bool { modeOverride == nil }
}

struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var date: Date
    var text: String
    var bundleID: String?
}

enum LocalStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Sotto", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func loadSettings() -> AppSettings {
        decode(AppSettings.self, name: "settings.json") ?? AppSettings()
    }

    static func save(settings: AppSettings) {
        encode(settings, name: "settings.json")
    }

    static func loadRulebook() -> Rulebook {
        decode(Rulebook.self, name: "rulebook.json") ?? Rulebook()
    }

    static func save(rulebook: Rulebook) {
        encode(rulebook, name: "rulebook.json")
    }

    static func loadHistory() -> [HistoryEntry] {
        decode([HistoryEntry].self, name: "history.json") ?? []
    }

    static func save(history: [HistoryEntry]) {
        encode(history, name: "history.json")
    }

    private static func decode<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, name: String) {
        let url = directory.appendingPathComponent(name)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

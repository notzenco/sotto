import Foundation
import Observation
import SottoCore

/// Kept dictation audio: `<id>.f32` (little-endian Float32 samples at 16 kHz) plus `<id>.json` per clip.
/// The record list lives on the main actor; file writes and deletes run in order on a background queue,
/// so saving a clip never holds up dictation.
@MainActor
@Observable
final class ClipStore {
    private(set) var records: [ClipRecord]

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let files: DispatchQueue

    /// Reads every readable record. Unreadable files are skipped.
    init(directory: URL) {
        self.directory = directory
        files = DispatchQueue(label: "app.sotto.desktop.clips", qos: .utility)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        records = Self.readRecords(in: directory)
    }

    func save(samples: [Float], record: ClipRecord) {
        records.append(record)
        let audio = audioURL(record.id)
        let json = recordURL(record.id)
        files.async {
            // Audio first, so a record on disk always has its audio.
            guard (try? Self.encode(samples).write(to: audio, options: .atomic)) != nil else { return }
            Self.write(record, to: json)
        }
    }

    /// Nil when the clip's audio is missing or unreadable. Waits for pending writes.
    func samples(for id: UUID) -> [Float]? {
        let url = audioURL(id)
        return files.sync {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return Self.decode(data)
        }
    }

    func update(_ record: ClipRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        let json = recordURL(record.id)
        files.async { Self.write(record, to: json) }
    }

    /// Deletes clips older than the retention period, plus stray files of that age that no record describes.
    func prune(now: Date) {
        let expired = Set(ClipRetention.expired(records, now: now).map(\.id))
        if !expired.isEmpty {
            records.removeAll { expired.contains($0.id) }
        }
        let kept = Set(records.map(\.id))
        let directory = directory
        files.async {
            let manager = FileManager.default
            let cutoff = now.addingTimeInterval(-TimeInterval(ClipRetention.days * 86_400))
            let contents = (try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in contents {
                if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                    if expired.contains(id) {
                        try? manager.removeItem(at: url)
                        continue
                    }
                    if kept.contains(id) { continue }
                }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified <= cutoff {
                    try? manager.removeItem(at: url)
                }
            }
        }
    }

    /// Removes every file in the clips folder, including ones no record describes.
    func deleteAll() {
        records = []
        let directory = directory
        files.async {
            let manager = FileManager.default
            for url in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                try? manager.removeItem(at: url)
            }
        }
    }

    private func audioURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).f32")
    }

    private func recordURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private nonisolated static func readRecords(in directory: URL) -> [ClipRecord] {
        let manager = FileManager.default
        let urls = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ClipRecord.self, from: data)
            }
            .sorted { $0.date < $1.date }
    }

    private nonisolated static func write(_ record: ClipRecord, to url: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func encode(_ samples: [Float]) -> Data {
        samples.map { $0.bitPattern.littleEndian }.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private nonisolated static func decode(_ data: Data) -> [Float]? {
        guard data.count % 4 == 0 else { return nil }
        return data.withUnsafeBytes { raw in
            (0..<(data.count / 4)).map {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
            }
        }
    }
}

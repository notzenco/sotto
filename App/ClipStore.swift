import Foundation
import Observation
import SottoCore
import os

/// Kept dictation audio: `<id>.f32` (little-endian Float32 samples at 16 kHz) plus `<id>.json` per clip.
/// The record list lives on the main actor; file writes and deletes run in order on a background queue,
/// so saving a clip never holds up dictation.
@MainActor
@Observable
final class ClipStore {
    private(set) var records: [ClipRecord]

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let files: DispatchQueue
    @ObservationIgnored private var pruneTimer: Timer?
    private nonisolated static let log = Logger(subsystem: "app.sotto.desktop", category: "dictation")

    /// Reads every readable record. Unreadable files are skipped.
    init(directory: URL) {
        self.directory = directory
        files = DispatchQueue(label: "app.sotto.desktop.clips", qos: .utility)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        records = Self.readRecords(in: directory)
    }

    /// A clip whose files can't be written is logged and dropped from `records`.
    func save(samples: [Float], record: ClipRecord) {
        records.append(record)
        let id = record.id
        let audio = audioURL(id)
        let json = recordURL(id)
        files.async { [weak self] in
            do {
                // Audio first, so a record on disk always has its audio.
                try Self.encode(samples).write(to: audio, options: .atomic)
                try Self.write(record, to: json)
            } catch {
                Self.log.error("clip not saved: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: audio)
                Task { @MainActor in self?.records.removeAll { $0.id == id } }
            }
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

    /// Like `samples(for:)`, but waits off the main actor.
    func loadSamples(for id: UUID) async -> [Float]? {
        let url = audioURL(id)
        let files = files
        return await withCheckedContinuation { continuation in
            files.async {
                continuation.resume(returning: (try? Data(contentsOf: url)).flatMap(Self.decode))
            }
        }
    }

    func update(_ record: ClipRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        let json = recordURL(record.id)
        files.async {
            do { try Self.write(record, to: json) }
            catch { Self.log.error("clip record not updated: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Checks every minute, so clips go after 7 days even on a Mac left running without dictation.
    /// The check is a filter over the records; files are only touched once a clip has expired.
    func startPruning() {
        pruneTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneIfExpired(now: Date()) }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    private func pruneIfExpired(now: Date) {
        guard !ClipRetention.expired(records, now: now).isEmpty else { return }
        prune(now: now)
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

    private nonisolated static func write(_ record: ClipRecord, to url: URL) throws {
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
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

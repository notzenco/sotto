import AVFoundation
import Foundation
import Observation

/// Plays one kept clip at a time from memory. The clip's samples become a WAV in memory; nothing is written to disk.
@MainActor
@Observable
final class ClipPlayer: NSObject, AVAudioPlayerDelegate {
    /// The clip playing, or loading to play.
    private(set) var playing: UUID?

    @ObservationIgnored private var player: AVAudioPlayer?
    /// The latest play request. A load whose request was replaced or stopped plays nothing.
    @ObservationIgnored private var request = UUID()

    /// Plays the clip, or stops it if it's the one playing.
    func toggle(_ id: UUID, clips: ClipStore) {
        if playing == id {
            stop()
            return
        }
        stop()
        playing = id
        let token = request
        Task {
            let samples = await clips.loadSamples(for: id)
            guard request == token else { return }
            guard let samples, !samples.isEmpty,
                  let player = try? AVAudioPlayer(data: Self.wav(samples)) else {
                playing = nil
                return
            }
            player.delegate = self
            self.player = player
            player.play()
        }
    }

    func stop() {
        request = UUID()
        player?.stop()
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(finished)
        Task { @MainActor in
            guard let player, ObjectIdentifier(player) == id else { return }
            stop()
        }
    }

    /// 16-bit mono PCM at the clips' 16 kHz.
    private static func wav(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        let bytes = samples.count * 2
        var data = Data(capacity: 44 + bytes)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(bytes))
        let pcm = samples.map { Int16((max(-1, min(1, $0)) * Float(Int16.max)).rounded()).littleEndian }
        pcm.withUnsafeBufferPointer { data.append($0) }
        return data
    }
}

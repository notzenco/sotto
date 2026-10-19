import AVFoundation
import Foundation
import Speech
import Synchronization

@MainActor
final class LiveLine {
    private(set) var text: String = ""
    var onChange: (@MainActor (String) -> Void)?

    private struct Chunk: Sendable {
        let sampleRate: Double
        let channels: Int
        let frames: Int
        let samples: [[Float]]
    }

    private struct Ingress: Sendable {
        var token: UUID?
        var accepting = false
        var chunks: [Chunk] = []
    }

    private nonisolated let ingress = Mutex(Ingress())
    private var token: UUID?
    private var committed = ""
    private var volatile = ""
    private var analyzer: SpeechAnalyzer?
    private var format: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var setupTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?
    private var modernConverter: AnyObject?

    func start() async {
        if token != nil { cancel() }
        let id = UUID()
        token = id
        ingress.withLock {
            $0.token = id
            $0.accepting = true
            $0.chunks.removeAll()
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepare(id)
        }
        setupTask = task
        await task.value
        guard token == id else { return }
        setupTask = nil
    }

    /// Called from the audio queue. AVAudioPCMBuffer is not Sendable, so copy the samples on the caller thread before hopping to the main actor.
    nonisolated func accept(_ buffer: AVAudioPCMBuffer) {
        let expectedID = ingress.withLock { $0.accepting ? $0.token : nil }
        guard let expectedID else { return }
        guard let source = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard channels > 0, buffer.format.sampleRate.isFinite,
              buffer.format.sampleRate > 0 else { return }
        let interleaved = buffer.format.isInterleaved
        let samples = (0..<channels).map { channel in
            (0..<frames).map { frame in
                interleaved ? source[0][frame * channels + channel] : source[channel][frame]
            }
        }
        let chunk = Chunk(sampleRate: buffer.format.sampleRate, channels: channels,
                          frames: frames, samples: samples)
        let id = ingress.withLock { state -> UUID? in
            guard state.accepting, let id = state.token, id == expectedID else { return nil }
            state.chunks.append(chunk)
            return id
        }
        guard let id else { return }
        Task { @MainActor [weak self] in
            self?.drain(id)
        }
    }

    func finish() async {
        guard let id = token else { return }
        ingress.withLock { $0.accepting = false }
        await setupTask?.value
        guard token == id else { return }
        drain(id)
        if #available(macOS 27, *), let modern = modernConverter as? AnalyzerInputConverter {
            do {
                for input in try modern.flush() { continuation?.yield(input) }
            } catch {
                disable(id)
                return
            }
        }
        continuation?.finish()
        await analysisTask?.value
        guard token == id else { return }
        await resultsTask?.value
        guard token == id else { return }
        releaseSession()
    }

    func cancel() {
        let oldAnalyzer = analyzer
        token = nil
        ingress.withLock {
            $0.token = nil
            $0.accepting = false
            $0.chunks.removeAll()
        }
        continuation?.finish()
        setupTask?.cancel()
        analysisTask?.cancel()
        resultsTask?.cancel()
        releaseSession()
        if let oldAnalyzer {
            Task { await oldAnalyzer.cancelAndFinishNow() }
        }
        committed = ""
        volatile = ""
        publish()
    }

    private func prepare(_ id: UUID) async {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        guard token == id, !Task.isCancelled else { return }
        guard let locale else {
            releaseSession()
            return
        }
        committed = ""
        volatile = ""
        publish()
        guard token == id else { return }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
            guard token == id, !Task.isCancelled else { return }
            if let request {
                try? await request.downloadAndInstall()
                guard token == id, !Task.isCancelled else { return }
            }
            let sessionAnalyzer = SpeechAnalyzer(modules: [transcriber], options: nil)
            analyzer = sessionAnalyzer
            let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            guard token == id, !Task.isCancelled else { return }
            guard let target else {
                disable(id)
                return
            }
            format = target
            if #available(macOS 27, *) {
                modernConverter = AnalyzerInputConverter(analyzerFormat: target)
            }
            let (stream, sink) = AsyncStream<AnalyzerInput>.makeStream()
            continuation = sink
            resultsTask = Task { @MainActor [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.token == id, !Task.isCancelled else { return }
                        let value = String(result.text.characters)
                        if result.isFinal {
                            self.committed += value
                            self.volatile = ""
                        } else {
                            self.volatile = value
                        }
                        self.publish()
                    }
                } catch {
                    self?.disable(id)
                }
            }
            analysisTask = Task { @MainActor [weak self] in
                do {
                    let end = try await sessionAnalyzer.analyzeSequence(stream)
                    guard let self, self.token == id, !Task.isCancelled else { return }
                    if let end {
                        try await sessionAnalyzer.finalizeAndFinish(through: end)
                        guard self.token == id, !Task.isCancelled else { return }
                    } else {
                        await sessionAnalyzer.cancelAndFinishNow()
                        guard self.token == id, !Task.isCancelled else { return }
                    }
                } catch {
                    self?.disable(id)
                }
            }
            drain(id)
        } catch {
            disable(id)
        }
    }

    private func drain(_ id: UUID) {
        guard token == id, continuation != nil, let format else { return }
        let chunks = ingress.withLock { state -> [Chunk] in
            guard state.token == id else { return [] }
            let chunks = state.chunks
            state.chunks.removeAll(keepingCapacity: true)
            return chunks
        }
        for chunk in chunks {
            guard token == id else { return }
            guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: chunk.sampleRate,
                                                    channels: AVAudioChannelCount(chunk.channels),
                                                    interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                                frameCapacity: AVAudioFrameCount(chunk.frames)),
                  let destination = buffer.floatChannelData else { continue }
            buffer.frameLength = AVAudioFrameCount(chunk.frames)
            for channel in 0..<chunk.channels {
                chunk.samples[channel].withUnsafeBufferPointer { samples in
                    if let base = samples.baseAddress {
                        destination[channel].update(from: base, count: chunk.frames)
                    }
                }
            }
            if #available(macOS 27, *), let modern = modernConverter as? AnalyzerInputConverter {
                do {
                    for input in try modern.convert(buffer, at: nil) { continuation?.yield(input) }
                } catch {
                    disable(id)
                    return
                }
            } else if sourceFormat == format {
                continuation?.yield(AnalyzerInput(buffer: buffer))
            } else {
                guard let output = convert(buffer, to: format) else { continue }
                continuation?.yield(AnalyzerInput(buffer: output))
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converterSource != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterSource = buffer.format
        }
        guard let converter else { return nil }
        let capacity = ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard capacity.isFinite, capacity > 0, capacity <= Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(capacity)) else {
            return nil
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private func disable(_ id: UUID) {
        guard token == id else { return }
        cancel()
    }

    private func releaseSession() {
        token = nil
        ingress.withLock {
            $0.token = nil
            $0.accepting = false
            $0.chunks.removeAll()
        }
        continuation = nil
        analyzer = nil
        format = nil
        setupTask = nil
        analysisTask = nil
        resultsTask = nil
        converter = nil
        converterSource = nil
        modernConverter = nil
    }

    private func publish() {
        text = committed + volatile
        onChange?(text)
    }
}

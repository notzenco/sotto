import AVFoundation
import Foundation
import Speech
import SottoCore

/// What LiveLine and AppleEngine share, so captions and Compare hear the same way.
///
/// DictationTranscriber rather than SpeechTranscriber: checked on macOS 27.2 with `say` samples, only
/// DictationTranscriber changed its words for contextual strings ("Quaker" became "Quokka").
enum AppleDictation {
    static func locale(for variety: SpellingVariety) async -> Locale? {
        await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: variety.localeIdentifier))
    }

    /// Progressive results drive the live captions. Never `.etiquetteReplacements`: Sotto types swearing as said.
    static func transcriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }

    /// Only the written forms; the misheard aliases would steer Apple toward the wrong words.
    /// Callers pass `Lexicon.contextualHints()`, already in priority order; this only enforces the cap.
    static func context(_ hints: [String]) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(hints.prefix(Lexicon.contextualHintLimit))
        return context
    }
}

/// Apple's built-in dictation in the spelling setting's English. Dictation itself takes its words from
/// LiveLine's session; this engine transcribes finished takes for Compare and the teacher.
/// Hints reach Apple as contextual strings, which change what it hears, so `raw` and `hinted` are always the same.
actor AppleEngine: SpeechEngine {
    nonisolated let id = SpeechModelID.appleEnglish
    private let variety: SpellingVariety
    private var loaded = false

    init(locale: SpellingVariety) {
        variety = locale
    }

    var isLoaded: Bool { loaded }

    /// Whether macOS has the locale installed. `AssetInventory.status` reads `supported` until Sotto
    /// reserves the locale, so it can't answer this.
    func isDownloaded() async -> Bool {
        guard let locale = await AppleDictation.locale(for: variety) else { return false }
        return await DictationTranscriber.installedLocales.contains { $0.identifier == locale.identifier }
    }

    /// Installs the locale if macOS lacks it. Asking also reserves the locale for Sotto.
    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws {
        if loaded { return }
        guard let locale = await AppleDictation.locale(for: variety) else { throw EngineError.unsupported(variety) }
        let transcriber = AppleDictation.transcriber(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { reported, _ in
                progress(reported.fractionCompleted)
            }
            defer { observation.invalidate() }
            try await request.downloadAndInstall()
        }
        progress(nil)
        loaded = true
    }

    func transcribe(_ samples: [Float], hints: [HintTerm]) async throws -> EngineResult? {
        guard samples.count >= 1600, samples.allSatisfy({ $0.isFinite }) else { return nil }
        guard loaded else { throw EngineError.notReady }
        guard let locale = await AppleDictation.locale(for: variety) else { throw EngineError.unsupported(variety) }

        let transcriber = AppleDictation.transcriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: nil)
        if !hints.isEmpty {
            try await analyzer.setContext(AppleDictation.context(hints.map(\.text)))
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let buffer = Self.buffer(samples, in: format) else { throw EngineError.audioFormat }

        let words = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        let (stream, sink) = AsyncStream<AnalyzerInput>.makeStream()
        sink.yield(AnalyzerInput(buffer: buffer))
        sink.finish()
        do {
            if let end = try await analyzer.analyzeSequence(stream) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            words.cancel()
            throw error
        }
        let text = try await words.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : EngineResult(raw: text, hinted: text)
    }

    func unload() {
        loaded = false
    }

    /// macOS owns Apple's speech assets.
    func deleteFiles() throws {}

    /// The 16 kHz mono take in the analyzer's format.
    private static func buffer(_ samples: [Float], in target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = input.floatChannelData?[0] else { return nil }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        if source == target { return input }

        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        let capacity = (Double(samples.count) * target.sampleRate / source.sampleRate).rounded(.up) + 32
        guard capacity.isFinite, capacity > 0, capacity <= Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(capacity)) else {
            return nil
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private enum EngineError: LocalizedError {
        case unsupported(SpellingVariety)
        case notReady
        case audioFormat

        var errorDescription: String? {
            switch self {
            case .unsupported(let variety): "macOS doesn't offer Apple dictation in \(variety.label) English."
            case .notReady: "Apple English isn't ready."
            case .audioFormat: "Apple English couldn't read the audio."
            }
        }
    }
}

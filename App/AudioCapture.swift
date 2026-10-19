import AVFoundation
import CoreAudio
import Foundation
import SottoCore

struct InputDevice: Identifiable, Equatable, Sendable {
    var id: AudioDeviceID
    var name: String
}

enum InputDevices {
    static func list() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let name = deviceName(id) else { return nil }
            return InputDevice(id: id, name: name)
        }
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        return status == noErr && size > 0
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name as String
    }
}

/// Captures the microphone as 16 kHz mono floats.
///
/// When the engine is running and no utterance is open, samples fill a 300 ms ring so the
/// first word is not cut off. The ring is overwritten and never written to disk.
final class AudioCapture: @unchecked Sendable {
    var onSamples: (@Sendable (AVAudioPCMBuffer, [Float]) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?

    var publishesLevel: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return levelPublishing
        }
        set {
            lock.lock()
            levelPublishing = newValue
            lock.unlock()
        }
    }

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )
    private let queue = DispatchQueue(label: "app.sotto.audio")
    private let lock = NSLock()
    // Accessed only on the audio queue, including resets.
    private var levelMeter = LevelMeter()
    private var levelPublishing = false
    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?
    private var ring = PreRoll(capacity: 4_800)
    private var utterance: [Float] = []
    private var recording = false
    private var tapInstalled = false

    func startEngine(deviceID: AudioDeviceID?) throws {
        try setDevice(deviceID)
        let input = engine.inputNode
        // Tap with the hardware format. The output format can lag a Bluetooth headset's switch
        // to its call profile, and a tap that disagrees with the hardware raises an
        // Objective-C exception that Swift cannot catch.
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInput
        }
        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.handle(buffer)
            }
            tapInstalled = true
        }
        engine.prepare()
        if !engine.isRunning {
            try engine.start()
        }
    }

    func stopEngine() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        queue.sync {
            levelMeter.reset()
        }
        lock.lock()
        ring.reset()
        utterance.removeAll(keepingCapacity: true)
        recording = false
        lock.unlock()
    }

    func beginUtterance() {
        lock.lock()
        utterance = ring.snapshot()
        recording = true
        lock.unlock()
    }

    func endUtterance() -> [Float] {
        lock.lock()
        recording = false
        let samples = utterance
        utterance.removeAll(keepingCapacity: true)
        lock.unlock()
        return samples
    }

    func cancelUtterance() {
        lock.lock()
        recording = false
        utterance.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private func setDevice(_ id: AudioDeviceID?) throws {
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        if let id, let unit = engine.inputNode.audioUnit {
            var device = id
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr { throw CaptureError.device }
        }
        if wasRunning { try engine.start() }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            let frames = Int(buffer.frameLength)
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return
        }
        queue.async { [weak self] in
            self?.convert(copy)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        guard let targetFormat else { return }
        let floats = resample(buffer, to: targetFormat)
        let level = levelMeter.ingest(floats)
        lock.lock()
        ring.append(floats)
        if recording {
            utterance.append(contentsOf: floats)
        }
        let callback = onSamples
        let levelCallback = levelPublishing ? onLevel : nil
        lock.unlock()
        callback?(buffer, floats)
        levelCallback?(level)
    }

    private func resample(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> [Float] {
        if converter == nil || converterSource != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterSource = buffer.format
        }
        guard let converter else { return [] }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: max(capacity, 1)) else { return [] }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, statusPointer in
            if consumed {
                statusPointer.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPointer.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, let channel = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    enum CaptureError: Error {
        case noInput
        case device
    }
}

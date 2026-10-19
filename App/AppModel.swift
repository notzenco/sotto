import AppKit
import AVFoundation
import CoreAudio
import KeyboardShortcuts
import SottoCore
import SwiftUI
import os

enum LevelWatcher: Hashable {
    case indicator, meter
}

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings
    var rulebook: Rulebook
    var history: [HistoryEntry]
    var modelPhase: ModelPhase = .missing
    var listening = false
    var inputLevel: Float = 0
    var accessibilityOn = false
    var microphoneOn = false
    var microphones: [InputDevice] = []
    var lastTranscript = ""

    var modelStatusLine: String {
        switch modelPhase {
        case .ready: "Ready"
        case .missing, .downloading: "Downloading the speech model…"
        case .failed(let reason): reason.isEmpty ? "Failed" : reason
        }
    }

    private var hold = HoldTracker()
    private let capture = AudioCapture()
    private var levelWatchers: Set<LevelWatcher> = []
    private let engine = ParakeetEngine()
    private let live = LiveLine()
    private let inserter = TextInserter()
    private let hotkeys = HotkeyMonitor()
    private let slip = SlipPanel()
    private let menu = MenuBarController()
    private var settingsWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var captured: FocusSnapshot?
    private var capturedDomain: String?
    private var engineRunning = false
    private var tapOn = false
    private var promptedForHotkey = false
    private var presentingPermission = false
    private var hotkeyWatch: Timer?
    private var tapStartedTrusted = false
    private var rightCommandDown = false
    private var hotkeyTicks = 0
    private var locked = false
    private var liveGeneration = 0
    private var postRollID: UUID?
    private var parkedSamples: [Float]?
    private let log = Logger(subsystem: "app.sotto.desktop", category: "dictation")

    init() {
        settings = LocalStore.loadSettings()
        rulebook = LocalStore.loadRulebook()
        history = LocalStore.loadHistory()
    }

    func installInterface() {
        menu.install(model: self)
    }

    func bootstrap() async {
        let box = UncheckedSendable(value: live)
        capture.onSamples = { buffer, _ in
            box.value.accept(buffer)
        }
        capture.onLevel = { level in
            Task { @MainActor in AppDelegateBridge.model?.inputLevel = level }
        }
        live.onChange = { [weak self] text in
            self?.provisional(text)
        }
        hotkeys.onRightCommand = { down in
            Task { @MainActor in AppDelegateBridge.model?.noteRightCommand(down, modifierRaw: 0) }
        }
        hotkeys.onEscape = {
            Task { @MainActor in AppDelegateBridge.model?.applyEscape() }
        }
        hotkeys.onChord = {
            Task { @MainActor in AppDelegateBridge.model?.applyChord() }
        }
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) {
            Task { @MainActor in AppDelegateBridge.model?.customHotkey(down: true) }
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) {
            Task { @MainActor in AppDelegateBridge.model?.customHotkey(down: false) }
        }

        microphoneOn = await Permissions.requestMicrophone()
        accessibilityOn = Permissions.accessibilityGranted()
        if microphoneOn, settings.keepFirstSyllable {
            startEngine()
        }
        syncHotkeySource()
        watchHotkey()
        modelPhase = .downloading
        Task { modelPhase = await engine.prepare() }
    }

    func setLevelWatching(_ on: Bool, for watcher: LevelWatcher) {
        if on {
            levelWatchers.insert(watcher)
        } else {
            levelWatchers.remove(watcher)
        }
        capture.publishesLevel = !levelWatchers.isEmpty
    }

    func refreshPermissions() {
        accessibilityOn = Permissions.accessibilityGranted()
        microphoneOn = Permissions.microphoneGranted()
    }

    func syncHotkeySource() {
        refreshPermissions()
        maintainTap()
        noteAccessibility()
        guard !accessibilityOn, !promptedForHotkey else { return }
        promptedForHotkey = true
        presentHotkeyPermission()
    }

    /// `activate()` does not take focus while another app is in front, so the prompt never appears.
    private func presentHotkeyPermission() {
        presentingPermission = true
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Permissions.promptForAccessibility()
            Permissions.openAccessibilitySettings()
            self.refreshPermissions()
            self.maintainTap()
            self.noteAccessibility()
            self.trace("prompted accessibility=\(self.accessibilityOn) tap=\(self.hotkeys.isEnabled)")
        }
    }

    private func noteAccessibility() {
        guard presentingPermission, accessibilityOn else { return }
        presentingPermission = false
        NSApp.setActivationPolicy(.accessory)
    }

    private func maintainTap() {
        if tapOn, accessibilityOn, !tapStartedTrusted {
            hotkeys.stop()
            tapOn = false
        }
        if !tapOn {
            tapOn = hotkeys.start()
            tapStartedTrusted = accessibilityOn
            trace("tap created \(tapOn) enabled \(hotkeys.isEnabled) trusted \(accessibilityOn)")
        } else {
            hotkeys.reenableIfNeeded()
        }
    }

    private func watchHotkey() {
        hotkeyWatch?.invalidate()
        let timer = Timer(timeInterval: 0.03, repeats: true) { _ in
            Task { @MainActor in
                let raw = UInt64(NSEvent.modifierFlags.rawValue)
                let keyDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(RightCommand.keyCode))
                let down = RightCommand.isHeld(modifierRaw: raw, keyIsDown: keyDown)
                AppDelegateBridge.model?.hotkeyTick(rightCommand: down, modifierRaw: raw)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hotkeyWatch = timer
        trace("poller started")
    }

    func hotkeyTick(rightCommand down: Bool, modifierRaw: UInt64) {
        hotkeyTicks += 1
        if hotkeyTicks == 1 || hotkeyTicks % 40 == 0 {
            refreshPermissions()
            maintainTap()
            noteAccessibility()
            if hotkeyTicks == 1 {
                trace("poller ticking modifiers=\(String(modifierRaw, radix: 16))")
            }
        }
        // With Accessibility on, the event tap reports Right Command. The poll reads system key
        // state, and when that disagrees it would end a hold the tap just started.
        guard !accessibilityOn else { return }
        noteRightCommand(down, modifierRaw: modifierRaw)
    }

    func noteRightCommand(_ down: Bool, modifierRaw: UInt64) {
        guard down != rightCommandDown else { return }
        rightCommandDown = down
        hotkeys.markRightCommand(down)
        trace("right command \(down ? "down" : "up") modifiers=\(String(modifierRaw, radix: 16))")
        rightCommand(down)
    }

    private func trace(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/sotto-hotkey.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func refreshMicrophones() {
        microphones = InputDevices.list()
    }

    func toggleFromMenu() {
        if hold.isLocked {
            apply(hold.hotkeyDown(at: Date()))
            return
        }
        if hold.isListening {
            apply(hold.hotkeyUp(at: Date()))
            return
        }
        let now = Date()
        _ = hold.hotkeyDown(at: now)
        _ = hold.hotkeyUp(at: now)
        apply(hold.hotkeyDown(at: now.addingTimeInterval(0.05)))
    }

    func rightCommand(_ down: Bool) {
        let event = down ? hold.hotkeyDown(at: Date()) : hold.hotkeyUp(at: Date())
        apply(event)
    }

    func customHotkey(down: Bool) {
        let event = down ? hold.hotkeyDown(at: Date()) : hold.hotkeyUp(at: Date())
        apply(event)
    }

    func applyEscape() {
        apply(hold.escape())
    }

    func applyChord() {
        apply(hold.chordKey())
    }

    func copyLastTranscript() {
        copy(lastTranscript)
    }

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func requestAccessibility() {
        presentHotkeyPermission()
    }

    func retryModel() {
        modelPhase = .downloading
        Task { modelPhase = await engine.prepare() }
    }

    func setKeepFirstSyllable(_ value: Bool) {
        settings.keepFirstSyllable = value
        LocalStore.save(settings: settings)
        if value, microphoneOn {
            startEngine()
        } else if !listening {
            capture.stopEngine()
            engineRunning = false
        }
    }

    func setHistoryHours(_ hours: Int) {
        settings.historyHours = hours
        LocalStore.save(settings: settings)
        if hours == 0 {
            history = []
            LocalStore.save(history: history)
        }
    }

    func setModeOverride(_ mode: DictationMode?) {
        settings.modeOverride = mode
        LocalStore.save(settings: settings)
    }

    func selectMicrophone(_ id: UInt32?) {
        settings.inputDeviceID = id
        LocalStore.save(settings: settings)
        guard engineRunning || settings.keepFirstSyllable else { return }
        capture.stopEngine()
        engineRunning = false
        startEngine()
    }

    func addReplacement(heard: String, written: String) {
        rulebook = rulebook.remember(heard: heard, written: written)
        LocalStore.save(rulebook: rulebook)
    }

    func deleteReplacement(id: UUID) {
        rulebook = rulebook.delete(id: id)
        LocalStore.save(rulebook: rulebook)
    }

    func openSettings() {
        refreshMicrophones()
        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView(model: self))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sotto"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.center()
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in AppDelegateBridge.model?.syncHotkeySource() }
            }
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func apply(_ event: HoldTracker.Event) {
        switch event {
        case .startHold, .startLocked:
            listening = true
            locked = event == .startLocked
            guard Permissions.microphoneGranted() else {
                listening = false
                locked = false
                _ = hold.escape()
                microphoneOn = false
                slip.showResult(text: "", failure: "Turn on Microphone")
                slip.hide(after: 4)
                return
            }
            beginTake()
        case .finish:
            listening = false
            locked = false
            let snapshot = captured
            let domain = capturedDomain
            let generation = liveGeneration
            Task { await commit(snapshot: snapshot, domain: domain, generation: generation) }
        case .cancel:
            listening = false
            locked = false
            if postRollID != nil {
                parkedSamples = capture.endUtterance()
                postRollID = nil
            } else {
                capture.cancelUtterance()
            }
            liveGeneration += 1
            live.cancel()
            slip.hideNow()
        case .ignore:
            break
        }
    }

    private func beginTake() {
        if postRollID != nil {
            parkedSamples = capture.endUtterance()
            postRollID = nil
        }
        if !engineRunning { startEngine() }
        captured = inserter.captureFocus()
        capturedDomain = inserter.lastDomain
        capture.beginUtterance()
        liveGeneration += 1
        Task { await live.start() }
        slip.showListening(word: settings.dictationCount < 3, provisional: "")
    }

    private func provisional(_ text: String) {
        guard listening else { return }
        slip.showListening(word: settings.dictationCount < 3 && text.isEmpty, provisional: text)
    }

    private func commit(snapshot: FocusSnapshot?, domain: String?, generation: Int) async {
        let started = Date()
        let roll = UUID()
        postRollID = roll
        try? await Task.sleep(nanoseconds: 60_000_000)
        let samples: [Float]
        if postRollID == roll {
            samples = capture.endUtterance()
            postRollID = nil
        } else {
            samples = parkedSamples ?? []
            parkedSamples = nil
        }
        if !settings.keepFirstSyllable, !listening {
            capture.stopEngine()
            engineRunning = false
        }
        let audioEnded = Date()

        let transcriptTask = Task { @MainActor () -> String? in
            guard self.modelPhase == .ready else { return nil }
            do { return try await self.engine.transcribe(samples) }
            catch { return nil }
        }
        let appleTask = Task { @MainActor () -> String in
            guard generation == self.liveGeneration else { return "" }
            await self.live.finish()
            return self.live.text
        }
        let transcript = await transcriptTask.value
        let apple = await appleTask.value
        let transcribed = Date()

        if modelPhase != .ready {
            present(text: apple, failure: apple.isEmpty ? "model downloading" : nil, hold: 4)
            if !apple.isEmpty { lastTranscript = apple }
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }

        let raw = transcript ?? (apple.isEmpty ? nil : apple)
        guard let raw, !raw.isEmpty else {
            present(text: "", failure: "not heard", hold: 4)
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }
        let mode = settings.modeOverride ?? AppIdentity.defaultMode(bundleID: snapshot?.bundleID, domain: domain)
        let formatted = rulebook.applying(to: TranscriptFormatter.format(raw, mode: mode))
        guard !formatted.isEmpty else {
            present(text: "", failure: "not heard", hold: 4)
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }

        let result: InsertResult
        if let snapshot, snapshot.pid != 0 {
            result = await inserter.insert(formatted, captured: snapshot)
        } else {
            result = .kept(.noTextField)
        }
        let injected = Date()
        switch result {
        case .inserted:
            present(text: formatted, failure: nil, hold: 1.2)
        case .kept(let problem):
            present(text: formatted.isEmpty ? "" : formatted, failure: problem.message, hold: 4)
        }
        lastTranscript = formatted
        settings.dictationCount += 1
        LocalStore.save(settings: settings)
        if settings.historyHours == 24 {
            history.append(HistoryEntry(id: UUID(), date: Date(), text: formatted, bundleID: snapshot?.bundleID))
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            history.removeAll { $0.date < cutoff }
            LocalStore.save(history: history)
        }
        logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: injected)
    }

    private func present(text: String, failure: String?, hold: TimeInterval) {
        guard !listening else { return }
        slip.showResult(text: text, failure: failure)
        slip.hide(after: hold)
    }

    private func logTiming(from started: Date, audio: Date, transcribed: Date, injected: Date) {
        let speech = Int(audio.timeIntervalSince(started) * 1000)
        let final = Int(transcribed.timeIntervalSince(started) * 1000)
        let injectedMS = Int(injected.timeIntervalSince(started) * 1000)
        log.info("speech_end \(speech, privacy: .public)ms final \(final, privacy: .public)ms injected \(injectedMS, privacy: .public)ms")
    }

    private func startEngine() {
        guard Permissions.microphoneGranted() else { return }
        do {
            try capture.startEngine(deviceID: settings.inputDeviceID)
            engineRunning = true
            microphoneOn = true
        } catch {
            engineRunning = false
        }
    }
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

/// Keyboard and notification callbacks cannot capture the main-actor model.
enum AppDelegateBridge {
    @MainActor static var model: AppModel? {
        (NSApp.delegate as? AppDelegate)?.model
    }
}

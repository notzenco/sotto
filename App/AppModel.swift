import AppKit
import AVFoundation
import CoreAudio
import KeyboardShortcuts
import ServiceManagement
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
    private(set) var settingsActivity = SettingsActivity()
    var accessibilityOn = false
    var microphoneOn = false
    private(set) var openAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginRequiresApproval = SMAppService.mainApp.status == .requiresApproval
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
    private let indicator = IndicatorPanel()
    private let menu = MenuBarController()
    private var settingsWindowController: SettingsWindowController?
    private var captured: FocusSnapshot?
    private var capturedDomain: String?
    private(set) var engineRunning = false
    private var tapOn = false
    private var promptedForHotkey = false
    private var presentingPermission = false
    private var hotkeyWatch: Timer?
    private var tapStartedTrusted = false
    private var rightCommandDown = false
    private var hotkeyTicks = 0
    private var locked = false
    private var takes = TakeLedger()
    private var postRollTake: TakeLedger.ID?
    private var parkedSamples: [TakeLedger.ID: [Float]] = [:]
    private let log = Logger(subsystem: "app.sotto.desktop", category: "dictation")

    init() {
        settings = LocalStore.loadSettings()
        rulebook = LocalStore.loadRulebook()
        history = LocalStore.loadHistory()
        indicator.apply(settings.indicator)
        indicator.onHide = { [weak self] in
            self?.setLevelWatching(false, for: .indicator)
        }
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
            Task { @MainActor in
                guard let model = AppDelegateBridge.model else { return }
                model.inputLevel = level
                model.indicator.setLevel(level)
            }
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

    func setSettingsWindowVisible(_ visible: Bool) {
        settingsActivity.windowVisible = visible
        setLevelWatching(settingsActivity.watchesMeter, for: .meter)
    }

    func setSettingsMicrophoneSelected(_ selected: Bool) {
        settingsActivity.microphoneSelected = selected
        setLevelWatching(settingsActivity.watchesMeter, for: .meter)
    }

    func refreshPermissions() {
        accessibilityOn = Permissions.accessibilityGranted()
        microphoneOn = Permissions.microphoneGranted()
    }

    func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        openAtLogin = status == .enabled
        loginRequiresApproval = status == .requiresApproval
    }

    func setOpenAtLogin(_ on: Bool) -> String? {
        defer { refreshLoginItem() }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func requestMicrophoneAccess() {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            Task {
                _ = await Permissions.requestMicrophone()
                refreshPermissions()
            }
        } else {
            Permissions.openMicrophoneSettings()
        }
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
        openSettings(pane: .privacy)
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
        let event = hold.escape()
        apply(event == .ignore && takes.isPending ? .cancel : event)
    }

    func applyChord() {
        let event = hold.chordKey()
        apply(event == .ignore && takes.isPending ? .cancel : event)
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

    func setIndicator(_ value: IndicatorSettings) {
        settings.indicator = value
        LocalStore.save(settings: settings)
        indicator.apply(value)
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

    func openSettings(pane: SettingsPane? = nil) {
        refreshMicrophones()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: self)
        }
        settingsWindowController?.show(pane: pane)
    }

    private func apply(_ event: HoldTracker.Event) {
        switch event {
        case .startHold, .startLocked:
            let take = takes.begin()
            listening = true
            locked = event == .startLocked
            guard Permissions.microphoneGranted() else {
                listening = false
                locked = false
                _ = hold.escape()
                microphoneOn = false
                indicator.show(.problem(.microphoneOff))
                takes.complete(take)
                return
            }
            beginTake(take)
        case .finish:
            guard let take = takes.finish() else { return }
            listening = false
            locked = false
            indicator.show(.working)
            let snapshot = captured
            let domain = capturedDomain
            // Assign audio ownership before the task can be delayed by another take.
            postRollTake = take
            Task { await commit(snapshot: snapshot, domain: domain, take: take) }
        case .cancel:
            guard let take = takes.cancel() else { return }
            listening = false
            locked = false
            if postRollTake == take { postRollTake = nil }
            parkedSamples.removeValue(forKey: take)
            capture.cancelUtterance()
            if !settings.keepFirstSyllable {
                capture.stopEngine()
                engineRunning = false
            }
            live.cancel(take)
            indicator.show(.cancelled)
        case .ignore:
            break
        }
    }

    private func beginTake(_ take: TakeLedger.ID) {
        if let previous = postRollTake {
            parkedSamples[previous] = capture.endUtterance()
            postRollTake = nil
        }
        if !engineRunning { startEngine() }
        captured = inserter.captureFocus()
        capturedDomain = inserter.lastDomain
        capture.beginUtterance()
        Task {
            guard takes.isCurrent(take) else { return }
            await live.start(take)
        }
        setLevelWatching(true, for: .indicator)
        indicator.show(.listening(handsFree: locked))
    }

    private func provisional(_ text: String) {
        guard listening else { return }
        indicator.setWords(text)
    }

    private func commit(snapshot: FocusSnapshot?, domain: String?, take: TakeLedger.ID) async {
        defer {
            takes.complete(take)
            parkedSamples.removeValue(forKey: take)
        }
        let started = Date()
        try? await Task.sleep(nanoseconds: 60_000_000)
        guard takes.allowsInsertion(take) else { return }
        let samples: [Float]
        if postRollTake == take {
            samples = capture.endUtterance()
            postRollTake = nil
        } else {
            samples = parkedSamples.removeValue(forKey: take) ?? []
        }
        if !settings.keepFirstSyllable, !listening, postRollTake == nil {
            capture.stopEngine()
            engineRunning = false
        }
        let audioEnded = Date()

        let transcriptTask = Task { @MainActor () -> String? in
            guard self.takes.allowsInsertion(take), self.modelPhase == .ready else { return nil }
            do { return try await self.engine.transcribe(samples) }
            catch { return nil }
        }
        let appleTask = Task { @MainActor () -> String in
            guard self.takes.allowsInsertion(take) else { return "" }
            // finish returns this session's text, even if a new session starts while it waits.
            return await self.live.finish(take)
        }
        let transcript = await transcriptTask.value
        guard takes.allowsInsertion(take) else { return }
        let apple = await appleTask.value
        guard takes.allowsInsertion(take) else { return }
        let transcribed = Date()

        if modelPhase != .ready {
            present(.problem(.modelDownloading), take: take)
            if !apple.isEmpty { lastTranscript = apple }
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }

        let raw = transcript ?? (apple.isEmpty ? nil : apple)
        guard let raw, !raw.isEmpty else {
            present(.problem(.notHeard), take: take)
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }
        let mode = settings.modeOverride ?? AppIdentity.defaultMode(bundleID: snapshot?.bundleID, domain: domain)
        let formatted = rulebook.applying(to: TranscriptFormatter.format(raw, mode: mode))
        guard !formatted.isEmpty else {
            present(.problem(.notHeard), take: take)
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }

        let result: InsertResult
        guard takes.allowsInsertion(take) else { return }
        if let snapshot, snapshot.pid != 0 {
            result = await inserter.insert(formatted, captured: snapshot) { [self] in
                takes.allowsInsertion(take)
            }
        } else {
            result = .kept(.noTextField)
        }
        guard takes.allowsInsertion(take) else { return }
        let injected = Date()
        switch result {
        case .inserted:
            present(.done, take: take)
        case .kept(let problem):
            present(.problem(problem), take: take)
        case .cancelled:
            return
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

    private func present(_ phase: IndicatorPhase, take: TakeLedger.ID) {
        guard takes.canPresent(take) else { return }
        indicator.show(phase)
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

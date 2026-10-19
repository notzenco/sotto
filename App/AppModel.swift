import AppKit
import AVFoundation
import CoreAudio
import KeyboardShortcuts
import NaturalLanguage
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
    var lexicon: Lexicon
    var history: [HistoryEntry]
    var listening = false
    var inputLevel: Float = 0
    private(set) var settingsActivity = SettingsActivity()
    var accessibilityOn = false
    var microphoneOn = false
    private(set) var openAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginRequiresApproval = SMAppService.mainApp.status == .requiresApproval
    var microphones: [InputDevice] = []
    var lastTranscript = ""
    let library: ModelLibrary
    let clips: ClipStore

    var modelPhase: ModelPhase { library.typingPhase }

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
    @ObservationIgnored private var teacher: TeacherScheduler?
    private let log = Logger(subsystem: "app.sotto.desktop", category: "dictation")

    init() {
        let settings = LocalStore.loadSettings()
        self.settings = settings
        rulebook = LocalStore.loadRulebook()
        lexicon = LocalStore.loadLexicon()
        history = LocalStore.loadHistory()
        library = ModelLibrary(typingModel: settings.typingModel, spelling: settings.spelling)
        clips = ClipStore(directory: LocalStore.clipsDirectory)
        teacher = TeacherScheduler(
            library: library, clips: clips,
            settings: { [unowned self] in self.settings },
            onSubstitution: { [weak self] substitution, clipID in
                self?.recordLearning(substitution, source: .teacher, clipID: clipID)
            })
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
        library.refreshDownloadStates()
        Task { await library.prepareTypingModel() }
        clips.prune(now: Date())
        warmSpelling(settings.spelling)
        teacher?.start()
    }

    /// Builds the spelling tables now rather than during the next dictation.
    private func warmSpelling(_ variety: SpellingVariety) {
        Task.detached(priority: .utility) { _ = SpellingConverter.convert("color", to: variety) }
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
        Task { await library.prepareTypingModel() }
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

    func setKeepAudio(_ on: Bool, deleteExisting: Bool) {
        settings.keepAudio = on
        LocalStore.save(settings: settings)
        if deleteExisting { clips.deleteAll() }
    }

    func deleteAllClips() {
        clips.deleteAll()
    }

    func setSpelling(_ variety: SpellingVariety) {
        settings.spelling = variety
        LocalStore.save(settings: settings)
        library.setSpelling(variety)
        warmSpelling(variety)
    }

    /// Typing stays on the current model until the new one is ready.
    func setTypingModel(_ id: SpeechModelID) {
        settings.typingModel = id
        LocalStore.save(settings: settings)
        Task { await library.select(id) }
    }

    /// Nil turns the teacher off.
    func setTeacherModel(_ id: SpeechModelID?) {
        settings.teacherModel = id
        LocalStore.save(settings: settings)
    }

    func addYourWord(_ word: String) {
        lexicon = lexicon.addingYourWord(word)
        LocalStore.save(lexicon: lexicon)
    }

    func removeYourWord(_ word: String) {
        lexicon = lexicon.removingYourWord(word)
        LocalStore.save(lexicon: lexicon)
    }

    func deleteLearnedWord(id: UUID) {
        lexicon = lexicon.deleting(id: id)
        LocalStore.save(lexicon: lexicon)
    }

    func recordLearning(_ s: Substitution, source: LearnSource, clipID: UUID?) {
        lexicon = lexicon.recording(s, source: source, clipID: clipID)
        LocalStore.save(lexicon: lexicon)
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
        teacher?.noteDictation()
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

        let typingModel = library.typingModel
        // Apple's engine is the live-caption session, so its final text is the typing model's result.
        let usesLiveText = typingModel == .appleEnglish
        let hints = usesLiveText ? [] : lexicon.hintTerms
        let transcriptTask = Task { @MainActor () -> EngineResult? in
            guard !usesLiveText, self.takes.allowsInsertion(take), self.modelPhase == .ready else { return nil }
            return await self.library.transcribeTyping(samples, hints: hints)
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

        // Without the typing model's result, the live text stands in for both, as Apple's engine produced it.
        let heard = transcript ?? EngineResult(raw: apple, hinted: apple)
        let clipModel = transcript == nil ? SpeechModelID.appleEnglish : typingModel
        guard !heard.hinted.isEmpty else {
            present(.problem(.notHeard), take: take)
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }
        let mode = settings.modeOverride ?? AppIdentity.defaultMode(bundleID: snapshot?.bundleID, domain: domain)
        var formatted = TranscriptFormatter.format(heard.hinted, mode: mode)
        let spelling = settings.spelling
        let respell: (String) -> String = mode == .prose ? { SpellingConverter.convert($0, to: spelling) } : { $0 }
        formatted = respell(formatted)
        // The owner's Names win over spelling, so each heard form also matches its respelled form.
        formatted = rulebook.applying(to: formatted, alsoMatching: respell)
        guard !formatted.isEmpty else {
            present(.problem(.notHeard), take: take)
            logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: Date())
            return
        }

        let result: InsertResult
        guard takes.allowsInsertion(take) else { return }
        if let snapshot, snapshot.pid != 0 {
            let before = snapshot.isSecureField || snapshot.secureInput
                ? nil : inserter.textBeforeCursor(bundleID: snapshot.bundleID)
            let fitted = InsertJoin.fit(formatted, before: before, mode: mode) { [self] word in
                keepsCapital(word, in: formatted)
            }
            result = await inserter.insert(fitted, captured: snapshot) { [self] in
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
        if settings.keepAudio, !samples.isEmpty {
            clips.save(samples: samples, record: ClipRecord(
                date: Date(), bundleID: snapshot?.bundleID, domain: domain,
                durationSeconds: Double(samples.count) / 16_000, typingModel: clipModel,
                rawText: heard.raw, hintedText: heard.hinted, typedText: formatted))
        }
        // Also while Keep audio is off, so clips kept from before still go after 7 days.
        clips.prune(now: Date())
        logTiming(from: started, audio: audioEnded, transcribed: transcribed, injected: injected)
    }

    /// Dictionary spellings and names keep their capital when a dictation continues a sentence.
    private func keepsCapital(_ word: String, in text: String) -> Bool {
        if rulebook.replacements.contains(where: { $0.written.split(separator: " ").contains { $0 == word } }) {
            return true
        }
        guard let start = text.range(of: word)?.lowerBound else { return false }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let tag = tagger.tag(at: start, unit: .word, scheme: .nameType).0
        return tag == .personalName || tag == .placeName || tag == .organizationName
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

import AppKit
import SwiftUI

/// The Compare window. Models run over the clips only while it's open; closing it stops them and any playback.
@MainActor
final class CompareWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var model: AppModel?
    private let runner: CompareRunner
    private let player = ClipPlayer()

    var isOpen: Bool { window.isVisible || window.isMiniaturized }

    init(model: AppModel, runner: CompareRunner) {
        self.model = model
        self.runner = runner
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Compare Models"
        window.minSize = NSSize(width: 520, height: 400)
        window.contentViewController = NSHostingController(
            rootView: CompareView(model: model, runner: runner, player: player)
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SottoCompare")
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        runner.start()
    }

    func windowWillClose(_ notification: Notification) {
        runner.stop()
        player.stop()
        // Settings may still be open, and keeps the app in the Dock while it is.
        if model?.isSettingsOpen != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

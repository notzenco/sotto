import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var model: AppModel?

    var isOpen: Bool { window.isVisible || window.isMiniaturized }

    init(model: AppModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Sotto Settings"
        window.minSize = NSSize(width: 720, height: 480)
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SottoSettings")
    }

    func show(pane: SettingsPane?) {
        if let pane {
            UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane")
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model?.syncHotkeySource()
    }
}

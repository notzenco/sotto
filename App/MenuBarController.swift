import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var model: AppModel?

    func install(model: AppModel) {
        self.model = model
        status.button?.image = MenuIcon.image()
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        model?.refreshPermissions()
        model?.syncHotkeySource()
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }

        let dictate = menu.addItem(
            withTitle: model.listening ? "Stop Dictation" : "Dictate",
            action: #selector(dictate(_:)),
            keyEquivalent: ""
        )
        dictate.target = self

        let copy = menu.addItem(
            withTitle: "Copy Last",
            action: #selector(copyLast(_:)),
            keyEquivalent: ""
        )
        copy.target = self
        copy.isEnabled = !model.lastTranscript.isEmpty

        let history = NSMenu()
        if model.settings.historyHours == 0 {
            history.addItem(withTitle: "History is off", action: nil, keyEquivalent: "")
        } else if model.history.isEmpty {
            history.addItem(withTitle: "No history", action: nil, keyEquivalent: "")
        } else {
            for entry in model.history.suffix(12).reversed() {
                let title = entry.text.replacingOccurrences(of: "\n", with: " ")
                let item = history.addItem(withTitle: title, action: #selector(copyHistory(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.text
            }
        }
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = history
        menu.addItem(historyItem)

        menu.addItem(.separator())
        switch model.modelPhase {
        case .ready:
            let item = menu.addItem(withTitle: "Speech model ready", action: nil, keyEquivalent: "")
            item.isEnabled = false
        case .missing, .downloading:
            let item = menu.addItem(withTitle: "Downloading the speech model…", action: nil, keyEquivalent: "")
            item.isEnabled = false
        case .failed:
            let item = menu.addItem(withTitle: "Speech model failed", action: nil, keyEquivalent: "")
            item.isEnabled = false
            let retry = menu.addItem(withTitle: "Retry", action: #selector(retry(_:)), keyEquivalent: "")
            retry.target = self
        }

        if !model.accessibilityOn {
            let waiting = menu.addItem(
                withTitle: "Right Command needs permission",
                action: #selector(accessibility(_:)),
                keyEquivalent: ""
            )
            waiting.target = self
        }
        if model.accessibilityOn {
            let item = menu.addItem(withTitle: "Accessibility on", action: nil, keyEquivalent: "")
            item.isEnabled = false
        } else {
            let item = menu.addItem(
                withTitle: "Turn on Accessibility",
                action: #selector(accessibility(_:)),
                keyEquivalent: ""
            )
            item.target = self
        }

        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings", action: #selector(settings(_:)), keyEquivalent: "")
        settings.target = self
        let quit = menu.addItem(withTitle: "Quit", action: #selector(quit(_:)), keyEquivalent: "")
        quit.target = self
    }

    @objc private func dictate(_ sender: Any?) { model?.toggleFromMenu() }
    @objc private func copyLast(_ sender: Any?) { model?.copyLastTranscript() }
    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        model?.copy(text)
    }
    @objc private func retry(_ sender: Any?) { model?.retryModel() }
    @objc private func accessibility(_ sender: Any?) { model?.requestAccessibility() }
    @objc private func settings(_ sender: Any?) { model?.openSettings() }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
}

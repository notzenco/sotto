import AppKit

enum MainMenu {
    @MainActor private static let actions = Actions()

    @MainActor
    static func install() {
        let main = NSMenu()

        let app = NSMenu(title: "Sotto")
        app.addItem(withTitle: "About Sotto", action: #selector(Actions.about(_:)), keyEquivalent: "")
            .target = actions
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(Actions.settings(_:)), keyEquivalent: ",")
            .target = actions
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Sotto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .target = NSApp
        add(app, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main)

        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    @MainActor
    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }

    @MainActor
    private final class Actions: NSObject {
        @objc func about(_ sender: Any?) { AppDelegateBridge.model?.openSettings(pane: .about) }
        @objc func settings(_ sender: Any?) { AppDelegateBridge.model?.openSettings() }
    }
}

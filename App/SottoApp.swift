import AppKit

@main
enum SottoMain {
    static func main() {
        let app = NSApplication.shared
        // The process starts on the main thread, before the main actor is entered.
        let delegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.installInterface()
        Task { await model.bootstrap() }
    }
}

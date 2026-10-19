import AppKit

/// One visibility signal for the retained microphone pane and indicator preview.
@MainActor
final class SettingsWindowVisibility: NSObject {
    private weak var window: NSWindow?
    private let changed: (Bool) -> Void
    private var closed = true

    init(window: NSWindow, changed: @escaping (Bool) -> Void) {
        self.window = window
        self.changed = changed
        super.init()
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(refresh), name: name, object: window
            )
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowClosing), name: NSWindow.willCloseNotification, object: window
        )
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(refresh), name: name, object: NSApp
            )
        }
    }

    /// Reopening a retained window does not always emit an occlusion notification.
    func shown() {
        closed = false
        refresh()
    }

    @objc private func windowClosing() {
        closed = true
        changed(false)
    }

    @objc private func refresh() {
        let visible = window.map {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        } ?? false
        changed(!closed && visible && !NSApp.isHidden)
    }
}

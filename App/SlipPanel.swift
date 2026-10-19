import AppKit

/// The line under the menu bar. It does not take focus and it is gone at rest.
@MainActor
final class SlipPanel {
    private let panel: NSPanel
    private let canvas = SlipCanvas()
    private var hideToken = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 232, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.contentView = canvas
    }

    func showListening(word: Bool, provisional: String) {
        hideToken += 1
        let line = provisional.isEmpty && word ? "listening" : provisional
        canvas.update(text: line, listening: true, word: provisional.isEmpty && word)
        place(fitting: line)
        panel.orderFrontRegardless()
    }

    func showResult(text: String, failure: String?) {
        hideToken += 1
        let line = (failure?.isEmpty == false) ? failure! : text
        canvas.update(text: line, listening: false, word: failure != nil)
        place(fitting: line)
        panel.orderFrontRegardless()
    }

    func hide(after seconds: TimeInterval) {
        hideToken += 1
        let token = hideToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard token == hideToken else { return }
            hideNow()
        }
    }

    func hideNow() {
        hideToken += 1
        panel.orderOut(nil)
    }

    private func place(fitting text: String) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let measured = (text as NSString).size(withAttributes: [.font: canvas.displayFont]).width
        let width = min(420, max(232, ceil(measured) + 36))
        let height: CGFloat = 28
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.maxY - height - 4,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
        canvas.frame = NSRect(origin: .zero, size: frame.size)
    }
}

private final class SlipCanvas: NSView {
    private var text = ""
    private var listening = false
    private var word = false
    private var dotAlpha: CGFloat = 1
    private var timer: Timer?

    var displayFont: NSFont {
        word ? Palette.newYork(size: 13) : NSFont.systemFont(ofSize: 12)
    }

    override var isOpaque: Bool { false }

    func update(text: String, listening: Bool, word: Bool) {
        self.text = text
        self.listening = listening
        self.word = word
        if listening {
            startPulse()
        } else {
            timer?.invalidate()
            timer = nil
            dotAlpha = 1
        }
        needsDisplay = true
    }

    private func startPulse() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let wave = (sin(Date.timeIntervalSinceReferenceDate * 2.2) + 1) / 2
            self.dotAlpha = 0.45 + 0.55 * wave
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        Palette.paper.setFill()
        path.fill()
        Palette.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()

        var textX: CGFloat = 10
        if listening {
            let dot = NSRect(x: 10, y: (bounds.height - 6) / 2, width: 6, height: 6)
            Palette.oxide.withAlphaComponent(dotAlpha).setFill()
            NSBezierPath(ovalIn: dot).fill()
            textX = 22
        }
        guard !text.isEmpty else { return }
        let font = displayFont
        let color = word ? Palette.ink : Palette.ink
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let y = (bounds.height - size.height) / 2
        let field = NSRect(x: textX, y: y, width: max(0, bounds.width - textX - 10), height: size.height)
        (text as NSString).draw(with: field, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}

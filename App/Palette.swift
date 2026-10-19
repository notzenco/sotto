import AppKit

enum Palette {
    static let paperLight = NSColor(srgbRed: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255, alpha: 1)
    static let paperDark = NSColor(srgbRed: 0x16 / 255, green: 0x14 / 255, blue: 0x11 / 255, alpha: 1)
    static let inkLight = NSColor(srgbRed: 0x1C / 255, green: 0x19 / 255, blue: 0x14 / 255, alpha: 1)
    static let inkDark = NSColor(srgbRed: 0xE8 / 255, green: 0xE1 / 255, blue: 0xD6 / 255, alpha: 1)
    static let graphiteLight = NSColor(srgbRed: 0x6B / 255, green: 0x64 / 255, blue: 0x5A / 255, alpha: 1)
    static let graphiteDark = NSColor(srgbRed: 0xA3 / 255, green: 0x9B / 255, blue: 0x90 / 255, alpha: 1)

    static var dark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static var paper: NSColor { dark ? paperDark : paperLight }
    static var ink: NSColor { dark ? inkDark : inkLight }
    static var graphite: NSColor { dark ? graphiteDark : graphiteLight }
}

enum MenuIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            let baseline = NSBezierPath()
            baseline.move(to: NSPoint(x: 3, y: 5.5))
            baseline.line(to: NSPoint(x: 15, y: 5.5))
            baseline.lineWidth = 1.15
            baseline.lineCapStyle = .round
            baseline.stroke()
            let slur = NSBezierPath()
            slur.move(to: NSPoint(x: 4, y: 7.2))
            slur.curve(
                to: NSPoint(x: 14, y: 7.2),
                controlPoint1: NSPoint(x: 7, y: 12.2),
                controlPoint2: NSPoint(x: 11, y: 12.2)
            )
            slur.lineWidth = 1.15
            slur.lineCapStyle = .round
            slur.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

import AppKit

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

import Foundation
import CoreGraphics

public struct ScreenGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var notch: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, notch: CGRect?) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.notch = notch
    }
}

public struct IndicatorPlacement: Equatable, Sendable {
    public var body: CGRect
    public var caption: CGRect?
    public var effectiveStyle: IndicatorStyle

    public init(body: CGRect, caption: CGRect?, effectiveStyle: IndicatorStyle) {
        self.body = body
        self.caption = caption
        self.effectiveStyle = effectiveStyle
    }
}

public enum IndicatorLayout {
    public static let edgeMargin: CGFloat = 16
    public static let topMargin: CGFloat = 8
    public static let caretGap: CGFloat = 8
    public static let captionGap: CGFloat = 6
    public static let maxBodyWidth: CGFloat = 420
    public static let maxCaptionWidth: CGFloat = 360

    public static func usableCaret(_ caret: CGRect?, screens: [ScreenGeometry]) -> CGRect? {
        guard let caret,
              caret.origin.x.isFinite, caret.origin.y.isFinite,
              caret.width.isFinite, caret.height.isFinite, caret.height > 0,
              screens.contains(where: { $0.frame.contains(CGPoint(x: caret.midX, y: caret.midY)) })
        else { return nil }
        return caret
    }

    public static func screenIndex(
        screens: [ScreenGeometry], display: IndicatorDisplay, position: IndicatorPosition,
        pointer: CGPoint, caret: CGRect?
    ) -> Int? {
        guard !screens.isEmpty else { return nil }
        if position == .caret, let caret = usableCaret(caret, screens: screens) {
            return screens.firstIndex { $0.frame.contains(CGPoint(x: caret.midX, y: caret.midY)) }
        }
        if display == .main { return 0 }
        return screens.firstIndex { $0.frame.contains(pointer) } ?? 0
    }

    public static func place(
        body: CGSize, caption: CGSize?, style: IndicatorStyle, position: IndicatorPosition,
        screen: ScreenGeometry, caret: CGRect?
    ) -> IndicatorPlacement {
        let availableWidth = max(0, screen.visibleFrame.width - edgeMargin)
        let bodySize = CGSize(width: min(body.width, maxBodyWidth, availableWidth), height: body.height)
        let captionSize = caption.map {
            CGSize(width: min($0.width, maxCaptionWidth, availableWidth), height: $0.height)
        }
        let caret = usableCaret(caret, screens: [screen])
        let position: IndicatorPosition = position == .caret && caret == nil ? .bottom : position

        func placement(at position: IndicatorPosition) -> IndicatorPlacement {
            var body = CGRect(origin: .zero, size: bodySize)
            body.origin.x = screen.visibleFrame.midX - body.width / 2
            if style == .notch {
                body.origin.x = (screen.notch?.midX ?? screen.frame.midX) - body.width / 2
                body.origin.y = screen.frame.maxY - body.height
            } else {
                switch position {
                case .bottom:
                    body.origin.y = screen.visibleFrame.minY + edgeMargin
                case .top:
                    body.origin.y = screen.visibleFrame.maxY - topMargin - body.height
                case .caret:
                    if let caret {
                        body.origin.x = caret.midX - body.width / 2
                        body.origin.y = caret.minY - caretGap - body.height
                        if body.minY < screen.visibleFrame.minY {
                            body.origin.y = caret.maxY + caretGap
                        }
                    }
                }
            }

            let caption = captionSize.map { size in
                if style == .dot {
                    return CGRect(x: body.maxX + captionGap, y: body.midY - size.height / 2,
                                  width: size.width, height: size.height)
                }
                let aboveCaret = position == .caret && caret.map { body.minY >= $0.maxY } == true
                let above = style == .pill && (position == .bottom || aboveCaret)
                return CGRect(x: body.midX - size.width / 2,
                              y: above ? body.maxY + captionGap : body.minY - captionGap - size.height,
                              width: size.width, height: size.height)
            }
            return IndicatorPlacement(body: body, caption: caption, effectiveStyle: style)
        }

        var result = placement(at: position)
        if let caret {
            let band = CGRect(x: screen.frame.minX, y: caret.minY - 2,
                              width: screen.frame.width, height: caret.height + 4)
            let occupied = result.caption.map { result.body.union($0) } ?? result.body
            if occupied.intersects(band) {
                if style == .notch {
                    if result.body.intersects(band) {
                        return place(body: body, caption: caption, style: .pill, position: .bottom,
                                     screen: screen, caret: caret)
                    }
                    if let caption = result.caption {
                        result.caption?.origin.y = band.minY - captionGap - caption.height
                    }
                } else if position == .bottom || position == .top {
                    result = placement(at: position == .bottom ? .top : .bottom)
                }
            }
        }

        func contained(_ rect: CGRect) -> CGRect {
            var rect = rect
            rect.origin.x = max(screen.visibleFrame.minX,
                                min(rect.minX, screen.visibleFrame.maxX - rect.width))
            // Containment takes precedence over caret clearance after placement.
            rect.origin.y = max(screen.frame.minY,
                                min(rect.minY, screen.frame.maxY - rect.height))
            return rect
        }
        result.body = contained(result.body)
        if style == .dot, var caption = result.caption {
            // Anchor to the contained dot, choosing the left side at the right edge.
            caption.origin.x = result.body.maxX + captionGap
            if caption.maxX > screen.visibleFrame.maxX {
                caption.origin.x = result.body.minX - captionGap - caption.width
            }
            result.caption = caption
        }
        result.caption = result.caption.map(contained)
        return result
    }
}

import AppKit
import Observation
import SottoCore
import struct SottoCore.RGBColor
import SwiftUI

@MainActor @Observable
final class IndicatorState {
    var phase: IndicatorPhase = .hidden
    var level: Float = 0
    var words = ""
    var settings = IndicatorSettings()
    var notch: CGRect? = nil
}

extension RGBColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

struct IndicatorView: View {
    let state: IndicatorState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch state.phase {
        case .hidden, .cancelled:
            EmptyView()
        default:
            Group {
                switch state.settings.style {
                case .pill:
                    VStack(spacing: IndicatorLayout.captionGap) {
                        if state.settings.position != .top { captionContent }
                        bodyContent
                        if state.settings.position == .top { captionContent }
                    }
                case .notch:
                    VStack(spacing: IndicatorLayout.captionGap) {
                        bodyContent
                        captionContent
                    }
                case .dot:
                    HStack(spacing: IndicatorLayout.captionGap) {
                        bodyContent
                        captionContent
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .allowsHitTesting(false)
        }
    }

    // Kept separate so the panel can position a caption independently when
    // IndicatorLayout moves it away from the caret.
    @ViewBuilder var bodyContent: some View {
        switch state.phase {
        case .hidden, .cancelled:
            EmptyView()
        default:
            switch state.settings.style {
            case .pill: pill
            case .notch: notch
            case .dot: dot
            }
        }
    }

    @ViewBuilder var captionContent: some View {
        if let size = Self.captionSize(for: state) {
            Text(state.words)
                .font(Font(Self.captionFont(scale: scale)))
                .foregroundStyle(RGBColor.paper.color.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 3 * scale)
                .frame(width: size.width, height: size.height)
                .background(Self.dark.opacity(0.72), in: RoundedRectangle(cornerRadius: 6 * scale))
        }
    }

    static func bodySize(for state: IndicatorState) -> CGSize {
        switch state.phase {
        case .hidden, .cancelled: return .zero
        default: break
        }
        let scale = scale(for: state)
        switch state.settings.style {
        case .pill:
            let width: CGFloat
            switch state.phase {
            case .listening(let handsFree): width = (78 + (handsFree ? 16 : 0)) * scale
            case .working: width = 46 * scale
            case .done: width = 32 * scale
            case .problem(let problem):
                width = min(IndicatorLayout.maxBodyWidth,
                            textSize(problem.message, font: problemFont(scale: scale)).width + 44 * scale)
            case .hidden, .cancelled: width = 0
            }
            return CGSize(width: width, height: 24 * scale)
        case .notch:
            return CGSize(width: (state.notch?.width ?? 0) + 2 * wingWidth(for: state),
                          height: max(state.notch?.height ?? 0, 24 * scale))
        case .dot:
            switch state.phase {
            case .listening(let handsFree):
                // A bounded radial glow keeps all drawing inside the panel.
                return CGSize(width: (50 + (handsFree ? 10 : 0)) * scale, height: 50 * scale)
            case .problem(let problem):
                return CGSize(width: min(IndicatorLayout.maxBodyWidth,
                                         textSize(problem.message, font: problemFont(scale: scale)).width
                                             + 56 * scale), height: 24 * scale)
            default:
                return CGSize(width: 14 * scale, height: 14 * scale)
            }
        }
    }

    static func captionSize(for state: IndicatorState) -> CGSize? {
        guard state.settings.showWords, case .listening = state.phase, !state.words.isEmpty else { return nil }
        let scale = scale(for: state)
        let text = textSize(state.words, font: captionFont(scale: scale))
        return CGSize(width: min(IndicatorLayout.maxCaptionWidth, text.width + 16 * scale),
                      height: text.height + 6 * scale)
    }

    private var scale: CGFloat { Self.scale(for: state) }
    private var bodySize: CGSize { Self.bodySize(for: state) }
    private var barColor: Color { state.settings.barColor.color }
    private var level: Double { state.level.isFinite ? Double(min(1, max(0, state.level))) : 0 }
    private var ink: Color {
        state.settings.style == .pill && state.settings.background == .light
            ? Color(.sRGB, red: 0.11, green: 0.11, blue: 0.12, opacity: 1)
            : RGBColor.paper.color
    }
    private static let dark = Color(.sRGB, red: 11 / 255, green: 11 / 255, blue: 12 / 255, opacity: 1)
    private static let light = Color(.sRGB, red: 244 / 255, green: 244 / 255, blue: 246 / 255, opacity: 1)

    private var pill: some View {
        pillContent
            .frame(width: max(0, bodySize.width - 24 * scale), height: bodySize.height)
            .padding(.horizontal, 12 * scale)
            .background {
                switch state.settings.background {
                case .dark: Capsule().fill(Self.dark)
                case .glass: Capsule().fill(.ultraThinMaterial)
                case .light: Capsule().fill(Self.light)
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    state.settings.background == .light ? Color.black.opacity(0.1) : Color.white.opacity(0.12),
                    lineWidth: 1
                )
            }
    }

    @ViewBuilder private var pillContent: some View {
        switch state.phase {
        case .listening(let handsFree):
            HStack(spacing: 6 * scale) {
                bars(count: 14)
                if handsFree { lock }
            }
        case .working: workingDots
        case .done: doneSymbol
        case .problem(let problem):
            HStack(spacing: 6 * scale) {
                problemSymbol
                problemText(problem.message)
            }
        case .hidden, .cancelled: EmptyView()
        }
    }

    private var notch: some View {
        let wing = Self.wingWidth(for: state)
        return HStack(spacing: 0) {
            ZStack { notchLeading }
                .frame(width: wing, height: bodySize.height)
                .background(.black)
            Color.clear.frame(width: state.notch?.width ?? 0, height: bodySize.height)
            ZStack { notchTrailing }
                .frame(width: max(0, wing - 10 * scale), height: bodySize.height)
                .padding(.horizontal, 5 * scale)
                .background(.black)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12 * scale, bottomTrailingRadius: 12 * scale))
    }

    @ViewBuilder private var notchLeading: some View {
        switch state.phase {
        case .listening:
            Circle().fill(Color(.sRGB, red: 1, green: 95 / 255, blue: 87 / 255, opacity: 1))
                .frame(width: 6 * scale, height: 6 * scale)
        case .working: symbol("waveform", color: ink)
        case .done: doneSymbol
        case .problem: problemSymbol
        case .hidden, .cancelled: EmptyView()
        }
    }

    @ViewBuilder private var notchTrailing: some View {
        switch state.phase {
        case .listening(let handsFree):
            HStack(spacing: 6 * scale) {
                bars(count: 10)
                if handsFree { lock }
            }
        case .working: workingDots
        case .problem(let problem): problemText(problem.message)
        case .done, .hidden, .cancelled: EmptyView()
        }
    }

    @ViewBuilder private var dot: some View {
        switch state.phase {
        case .listening(let handsFree):
            HStack(spacing: 0) {
                ZStack {
                    Circle().fill(RadialGradient(
                        colors: [barColor.opacity(0.55), barColor.opacity(0)],
                        center: .center, startRadius: 5 * scale,
                        endRadius: (reduceMotion ? 11 : 11 + 14 * level) * scale
                    ))
                    Circle().fill(barColor).frame(width: 14 * scale, height: 14 * scale)
                }
                .frame(width: 50 * scale, height: 50 * scale)
                .opacity(reduceMotion ? 0.35 + 0.65 * level : 1)
                if handsFree { lock }
            }
        case .working: workingDots.frame(width: bodySize.width, height: bodySize.height)
        case .done: doneSymbol.frame(width: bodySize.width, height: bodySize.height)
        case .problem(let problem):
            HStack(spacing: 6 * scale) {
                Circle().fill(barColor).frame(width: 14 * scale, height: 14 * scale)
                HStack(spacing: 6 * scale) {
                    problemSymbol
                    problemText(problem.message)
                }
                .padding(.horizontal, 8 * scale)
                .frame(height: bodySize.height)
                .background(Self.dark, in: Capsule())
            }
            .frame(width: bodySize.width, height: bodySize.height)
        case .hidden, .cancelled: EmptyView()
        }
    }

    @ViewBuilder private func bars(count: Int) -> some View {
        if reduceMotion {
            barRow(heights: [Float](repeating: 0.5, count: count))
                .opacity(0.35 + 0.65 * level)
        } else {
            TimelineView(.animation) { context in
                barRow(heights: IndicatorBars.heights(
                    level: state.level, count: count, time: context.date.timeIntervalSinceReferenceDate
                ))
            }
        }
    }

    private func barRow(heights: [Float]) -> some View {
        HStack(spacing: 2 * scale) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule().fill(barColor)
                    .frame(width: 2 * scale, height: 14 * scale * CGFloat(heights[index]))
            }
        }
        .frame(height: 14 * scale)
    }

    @ViewBuilder private var workingDots: some View {
        if reduceMotion {
            dotRow(time: nil)
        } else {
            TimelineView(.animation) { context in
                dotRow(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func dotRow(time: Double?) -> some View {
        HStack(spacing: 2 * scale) {
            ForEach(0..<3) { index in
                Circle().fill(barColor)
                    .frame(width: 3 * scale, height: 3 * scale)
                    .opacity(time.map { 0.25 + 0.75 * (sin($0 * 2 * .pi - Double(index) * 0.9) + 1) / 2 } ?? 1)
            }
        }
    }

    private var lock: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9 * scale, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: 10 * scale, height: 14 * scale)
    }

    private var doneSymbol: some View { symbol("checkmark", color: RGBColor.green.color) }
    private var problemSymbol: some View { symbol("exclamationmark.circle", color: RGBColor.orange.color) }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 12 * scale, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 14 * scale, height: 14 * scale)
    }

    private func problemText(_ message: String) -> some View {
        Text(message)
            .font(Font(Self.problemFont(scale: scale)))
            .foregroundStyle(ink)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private static func scale(for state: IndicatorState) -> CGFloat {
        let size = state.settings.size
        return CGFloat(size.isFinite ? min(1.5, max(0.8, size)) : 1)
    }

    private static func problemFont(scale: CGFloat) -> NSFont { .systemFont(ofSize: 12 * scale) }
    private static func captionFont(scale: CGFloat) -> NSFont { .systemFont(ofSize: 11 * scale) }

    private static func textSize(_ text: String, font: NSFont) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private static func wingWidth(for state: IndicatorState) -> CGFloat {
        let scale = scale(for: state)
        switch state.phase {
        case .problem(let problem):
            return max(48 * scale, min(
                textSize(problem.message, font: problemFont(scale: scale)).width + 10 * scale,
                max(0, (IndicatorLayout.maxBodyWidth - (state.notch?.width ?? 0)) / 2)
            ))
        case .listening(handsFree: true): return 64 * scale
        default: return 48 * scale
        }
    }

    private var accessibilityText: String {
        let phase: String
        switch state.phase {
        case .listening(let handsFree): phase = handsFree ? "Listening, hands-free" : "Listening"
        case .working: phase = "Working"
        case .done: phase = "Done"
        case .problem(let problem): phase = problem.message
        case .hidden, .cancelled: return ""
        }
        return Self.captionSize(for: state) == nil ? phase : "\(phase). \(state.words)"
    }
}

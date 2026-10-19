import AppKit
import SottoCore
import struct SottoCore.RGBColor
import SwiftUI

struct IndicatorPane: View {
    var model: AppModel
    var windowVisible: Bool

    var body: some View {
        Form {
            Section {
                IndicatorPreview(settings: model.settings.indicator, windowVisible: windowVisible)
            }
            Section {
                Picker("Style", selection: selection(\.style)) {
                    Text("Pill").tag(IndicatorStyle.pill)
                    Text("Notch").tag(IndicatorStyle.notch)
                    Text("Dot").tag(IndicatorStyle.dot)
                }
                .pickerStyle(.segmented)

                if model.settings.indicator.style != .notch {
                    Picker("Position", selection: selection(\.position)) {
                        Text("Bottom").tag(IndicatorPosition.bottom)
                        Text("Top").tag(IndicatorPosition.top)
                        Text("At the text cursor").tag(IndicatorPosition.caret)
                    }
                    .pickerStyle(.segmented)
                }

                Slider(value: selection(\.size), in: IndicatorSettings.sizeRange, step: 0.05) {
                    Text("Size")
                }
                colorControls

                if model.settings.indicator.style == .pill {
                    Picker("Background", selection: selection(\.background)) {
                        Text("Dark").tag(IndicatorBackground.dark)
                        Text("Glass").tag(IndicatorBackground.glass)
                        Text("Light").tag(IndicatorBackground.light)
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(isOn: selection(\.showWords)) {
                    Text("Show words as you talk")
                    Text("What Sotto thinks it heard, before it types")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Show on", selection: selection(\.display)) {
                    Text("Display with the mouse pointer").tag(IndicatorDisplay.pointer)
                    Text("Main display").tag(IndicatorDisplay.main)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var colorControls: some View {
        LabeledContent("Bar colour") {
            HStack(spacing: 7) {
                ForEach(RGBColor.presets, id: \.self) { preset in
                    Button {
                        selection(\.barColor).wrappedValue = preset
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1) }
                            .padding(3)
                            .overlay {
                                Circle().strokeBorder(
                                    model.settings.indicator.barColor == preset ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                            }
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presetName(preset))
                    .accessibilityAddTraits(model.settings.indicator.barColor == preset ? .isSelected : [])
                }
                ColorPicker("Custom colour", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private func selection<Value>(_ keyPath: WritableKeyPath<IndicatorSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings.indicator[keyPath: keyPath] },
            set: { value in
                var updated = model.settings.indicator
                updated[keyPath: keyPath] = value
                model.setIndicator(updated)
            }
        )
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { model.settings.indicator.barColor.color },
            set: { value in
                guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
                selection(\.barColor).wrappedValue = RGBColor(
                    red: Double(color.redComponent), green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                )
            }
        )
    }

    private func presetName(_ color: RGBColor) -> String {
        switch color {
        case .paper: "Paper"
        case .white: "White"
        case .blue: "Blue"
        case .green: "Green"
        case .pink: "Pink"
        case .orange: "Orange"
        default: color.hex
        }
    }
}

private struct IndicatorPreview: View {
    var settings: IndicatorSettings
    var windowVisible: Bool
    @State private var state = IndicatorState()
    @State private var timer: Timer?
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [Color(red: 0.23, green: 0.29, blue: 0.48),
                             Color(red: 0.12, green: 0.14, blue: 0.25),
                             Color(red: 0.07, green: 0.07, blue: 0.12)],
                    center: .topLeading, startRadius: 0, endRadius: geometry.size.width
                )
                Color.black.opacity(0.35).frame(height: 16)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black)
                    .frame(width: 70, height: 16)
                HStack(spacing: 2) {
                    Text("keen for a servo run this")
                        .font(.system(size: 11))
                    Rectangle().frame(width: 1, height: 12)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(width: geometry.size.width * 0.46, height: 22)
                .background(Color(red: 0.22, green: 0.23, blue: 0.25), in: RoundedRectangle(cornerRadius: 6))
                .position(x: geometry.size.width * 0.35, y: 93)

                IndicatorView(state: state)
                    .scaleEffect(previewScale(in: geometry.size))
                    .position(indicatorCenter(in: geometry.size))
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.12)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live indicator preview")
        .onAppear {
            appeared = true
            state.phase = .listening(handsFree: false)
            state.settings = settings
            state.notch = CGRect(x: 0, y: 0, width: 70, height: 16)
            updateTimer()
        }
        .onChange(of: settings) { _, value in state.settings = value }
        .onChange(of: windowVisible) { _, _ in updateTimer() }
        .onDisappear {
            appeared = false
            stopTimer()
        }
    }

    private var indicatorSize: CGSize {
        let body = IndicatorView.bodySize(for: state)
        let caption = IndicatorView.captionSize(for: state)
        let gap = caption == nil ? 0 : IndicatorLayout.captionGap
        let height = settings.style == .dot ? max(body.height, caption?.height ?? 0)
            : body.height + (caption?.height ?? 0) + gap
        let width = settings.style == .dot ? body.width + (caption?.width ?? 0) + gap
            : max(body.width, caption?.width ?? 0)
        return CGSize(width: width, height: height)
    }

    private func previewScale(in size: CGSize) -> CGFloat {
        min(1, max(0, size.width - 8) / max(1, indicatorSize.width))
    }

    private func indicatorCenter(in size: CGSize) -> CGPoint {
        let scale = previewScale(in: size)
        let width = indicatorSize.width * scale
        let height = indicatorSize.height * scale
        let x: CGFloat = settings.style != .notch && settings.position == .caret ? size.width * 0.4 : size.width / 2
        let y: CGFloat
        if settings.style == .notch {
            y = height / 2
        } else {
            switch settings.position {
            case .bottom: y = size.height - 10 - height / 2
            case .top: y = 22 + height / 2
            case .caret: y = 108 + height / 2
            }
        }
        // Keep long captions inside the miniature screen at every size.
        return CGPoint(x: min(max(x, width / 2 + 4), size.width - width / 2 - 4),
                       y: min(y, size.height - height / 2 - 4))
    }

    private func updateTimer() {
        guard appeared && windowVisible else {
            stopTimer()
            return
        }
        guard timer == nil else { return }
        let start = Date.timeIntervalSinceReferenceDate
        let words = "yo what's up my G, keen for a servo run this arvo?".split(separator: " ")
        let previewState = state
        previewState.words = String(words[0])
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            // This timer is installed only on the main run loop.
            MainActor.assumeIsolated {
                let elapsed = Date.timeIntervalSinceReferenceDate - start
                let syllable = (sin(elapsed * 14) + 1) / 2
                let phrase = (sin(elapsed * 2.3) + 1) / 2
                previewState.level = Float(0.08 + 0.85 * syllable * phrase)
                let count = min(words.count, Int(elapsed.truncatingRemainder(dividingBy: 5.2) / 5.2 * Double(words.count)) + 1)
                previewState.words = words.prefix(count).joined(separator: " ")
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

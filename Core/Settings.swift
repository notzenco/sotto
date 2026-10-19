import Foundation

public enum IndicatorStyle: String, Codable, CaseIterable, Sendable {
    case pill, notch, dot
}

public enum IndicatorPosition: String, Codable, CaseIterable, Sendable {
    case bottom, top, caret
}

public enum IndicatorBackground: String, Codable, CaseIterable, Sendable {
    case dark, glass, light
}

public enum IndicatorDisplay: String, Codable, CaseIterable, Sendable {
    case pointer, main
}

public struct RGBColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#",
              hex.dropFirst().utf8.allSatisfy({
                  (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
              }),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public var hex: String {
        String(format: "#%02X%02X%02X",
               Int((min(max(red, 0), 1) * 255).rounded()),
               Int((min(max(green, 0), 1) * 255).rounded()),
               Int((min(max(blue, 0), 1) * 255).rounded()))
    }

    public static let paper = RGBColor(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    public static let white = RGBColor(red: 1, green: 1, blue: 1)
    public static let blue = RGBColor(red: 90 / 255, green: 200 / 255, blue: 250 / 255)
    public static let green = RGBColor(red: 126 / 255, green: 224 / 255, blue: 161 / 255)
    public static let pink = RGBColor(red: 1, green: 126 / 255, blue: 182 / 255)
    public static let orange = RGBColor(red: 1, green: 179 / 255, blue: 64 / 255)
    public static let presets: [RGBColor] = [paper, white, blue, green, pink, orange]
}

public struct IndicatorSettings: Codable, Equatable, Sendable {
    public var style: IndicatorStyle = .pill
    public var position: IndicatorPosition = .bottom
    public var size: Double = 1.0
    public var barColor: RGBColor = .paper
    public var background: IndicatorBackground = .dark
    public var showWords: Bool = false
    public var display: IndicatorDisplay = .pointer

    public static let sizeRange: ClosedRange<Double> = 0.8...1.5

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case style, position, size, barColor, background, showWords, display
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? container.decodeIfPresent(IndicatorStyle.self, forKey: .style)) ?? style
        position = (try? container.decodeIfPresent(IndicatorPosition.self, forKey: .position)) ?? position
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? size
        size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        barColor = (try? container.decodeIfPresent(RGBColor.self, forKey: .barColor)) ?? barColor
        background = (try? container.decodeIfPresent(IndicatorBackground.self, forKey: .background)) ?? background
        showWords = try container.decodeIfPresent(Bool.self, forKey: .showWords) ?? showWords
        display = (try? container.decodeIfPresent(IndicatorDisplay.self, forKey: .display)) ?? display
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var keepFirstSyllable: Bool = true
    /// Zero means history is off. Twenty-four keeps text for a day on this Mac.
    public var historyHours: Int = 0
    /// Nil follows the focused app. A value forces Prose or Literal.
    public var modeOverride: DictationMode? = nil
    public var inputDeviceID: UInt32? = nil
    public var dictationCount: Int = 0
    public var indicator: IndicatorSettings = .init()

    public var automaticMode: Bool { modeOverride == nil }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case keepFirstSyllable, historyHours, modeOverride, inputDeviceID, dictationCount, indicator
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keepFirstSyllable = try container.decodeIfPresent(Bool.self, forKey: .keepFirstSyllable) ?? keepFirstSyllable
        historyHours = try container.decodeIfPresent(Int.self, forKey: .historyHours) ?? historyHours
        modeOverride = (try? container.decodeIfPresent(DictationMode.self, forKey: .modeOverride)) ?? modeOverride
        inputDeviceID = try container.decodeIfPresent(UInt32.self, forKey: .inputDeviceID) ?? inputDeviceID
        dictationCount = try container.decodeIfPresent(Int.self, forKey: .dictationCount) ?? dictationCount
        indicator = try container.decodeIfPresent(IndicatorSettings.self, forKey: .indicator) ?? indicator
    }
}

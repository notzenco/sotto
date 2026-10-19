import Foundation

/// Converts microphone samples into a smoothed level between zero and one.
public struct LevelMeter: Sendable {
    public private(set) var level: Float = 0

    private let floorDecibels: Float
    private let attack: Float
    private let release: Float

    public init(floorDecibels: Float = -50, attack: Float = 0.6, release: Float = 0.15) {
        self.floorDecibels = floorDecibels
        self.attack = attack
        self.release = release
    }

    public mutating func ingest(_ samples: [Float]) -> Float {
        var sumOfSquares: Double = 0
        var count = 0
        for sample in samples where sample.isFinite {
            let value = Double(sample)
            sumOfSquares += value * value
            count += 1
        }
        guard count > 0 else { return level }
        let rms = Float(sqrt(sumOfSquares / Double(count)))
        let target = Self.normalized(rms: rms, floorDecibels: floorDecibels)
        level += (target - level) * (target > level ? attack : release)
        return level
    }

    public mutating func reset() {
        level = 0
    }

    public static func normalized(rms: Float, floorDecibels: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }
}

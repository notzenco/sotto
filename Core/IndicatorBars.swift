import Foundation

public enum IndicatorBars {
    public static let floor: Float = 0.14

    public static func heights(level: Float, count: Int, time: Double) -> [Float] {
        guard count > 0 else { return [] }
        let level = level.isFinite ? min(1, max(0, level)) : 0
        let mid = Float(count - 1) / 2
        return (0..<count).map { index in
            let shape: Float = mid == 0 ? 1 : 1 - abs(Float(index) - mid) / mid * 0.55
            let wobble = 0.8 + 0.2 * sin(time * 7 + Double(index) * 1.7)
            return min(1, max(floor, level * shape * Float(wobble)))
        }
    }
}

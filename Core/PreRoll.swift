import Foundation

/// A fixed window of recent samples. The oldest samples fall off the front.
public struct PreRoll: Sendable {
    public let capacity: Int
    private var samples: [Float] = []

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    public var count: Int { samples.count }

    public mutating func append(_ incoming: [Float]) {
        guard capacity > 0, !incoming.isEmpty else { return }
        samples.append(contentsOf: incoming)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public func snapshot() -> [Float] {
        samples
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}

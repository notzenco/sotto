import Foundation

/// Take identity is independent of the held-key state and the live recognizer.
public struct TakeLedger: Sendable {
    public typealias ID = UUID
    public private(set) var current: ID?
    private var pending: Set<ID> = []

    public init() {}

    public var isPending: Bool { current.map { pending.contains($0) } ?? false }

    public mutating func begin() -> ID {
        let id = UUID()
        current = id
        return id
    }

    public mutating func finish() -> ID? {
        guard let current, !isPending else { return nil }
        pending.insert(current)
        return current
    }

    public mutating func cancel() -> ID? {
        guard let current else { return nil }
        pending.remove(current)
        self.current = nil
        return current
    }

    public func isCurrent(_ id: ID) -> Bool { current == id }
    /// A superseded take may still insert its own text; cancellation removes that right.
    public func allowsInsertion(_ id: ID) -> Bool { pending.contains(id) }
    public func canPresent(_ id: ID) -> Bool { isCurrent(id) && allowsInsertion(id) }

    public mutating func complete(_ id: ID) {
        pending.remove(id)
        if current == id { current = nil }
    }
}

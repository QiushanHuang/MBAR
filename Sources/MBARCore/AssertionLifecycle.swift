// Owns abstract handle IDs; the runtime bridge owns actual OS objects.
public struct AssertionLifecycle {
    public private(set) var active: Int?
    public private(set) var pending: Int?
    public init() {}
    public mutating func begin(_ id: Int) -> [Int] {
        let release = pending.map { [$0] } ?? []
        pending = id
        return release
    }
    public mutating func complete(_ id: Int, success: Bool) -> [Int] {
        guard pending == id else { return active == id ? [] : [id] }
        pending = nil
        guard success else { return [id] }
        let release = active.map { [$0] } ?? []
        active = id
        return release
    }
    public mutating func restore() -> [Int] {
        let release = [active, pending].compactMap { $0 }
        active = nil; pending = nil
        return release
    }
}

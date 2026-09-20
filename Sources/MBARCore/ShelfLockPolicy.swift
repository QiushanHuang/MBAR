public enum ShelfCloseReason {
    case outside, escape, toggle, item, settings, applicationsChanged, recovery
}

public struct ShelfLockPolicy: Equatable {
    public private(set) var showsButton: Bool
    public private(set) var isLocked = false
    public init(showsButton: Bool) { self.showsButton = showsButton }
    public mutating func toggle() { if showsButton { isLocked.toggle() } }
    public mutating func setShowsButton(_ value: Bool) {
        showsButton = value
        if !value { isLocked = false }
    }
    public mutating func unlock() { isLocked = false }
    public func shouldClose(for reason: ShelfCloseReason) -> Bool {
        reason == .recovery || !isLocked
    }
}

import Foundation

/// AX can report final positions before the compositor finishes animating.
/// Require both a minimum settling interval and an unchanged layout, with a
/// caller-owned deadline. This is a conservative heuristic, not an OS callback.
public struct NativeTransitionGate {
    private let startedAt: TimeInterval
    private var signature: [String]?
    private var unchangedSince: TimeInterval?
    public init(startedAt: TimeInterval) { self.startedAt = startedAt }
    public mutating func observe(_ sample: [String]?, at now: TimeInterval) -> Bool {
        guard let sample, !sample.isEmpty else {
            signature = nil; unchangedSince = nil; return false
        }
        if sample != signature { signature = sample; unchangedSince = now }
        return now - startedAt >= 0.5 && now - (unchangedSince ?? now) >= 0.25
    }
}

/// Only the most recent capture that actually expanded overflow may restore it.
public struct OverflowLease {
    private var owner: UUID?
    public init() {}
    public mutating func claim() -> UUID { let id = UUID(); owner = id; return id }
    public mutating func consume(_ id: UUID) -> Bool {
        guard owner == id else { return false }
        owner = nil; return true
    }
}

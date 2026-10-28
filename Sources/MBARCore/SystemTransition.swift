/// Tokens bind asynchronous layout/AX work to the latest system environment.
/// Display notifications received during sleep must not wake the hiding client.
public struct MenuBarSystemTransition {
    public private(set) var sleeping = false
    private var generation = 0
    public init() {}
    @discardableResult public mutating func begin(sleeping: Bool? = nil) -> Int {
        if let sleeping { self.sleeping = sleeping }
        generation += 1
        return generation
    }
    public func canResume(_ token: Int) -> Bool { !sleeping && token == generation }
}

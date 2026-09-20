import Foundation
import CoreGraphics
public struct VisibilityState {
    public enum Phase: Equatable { case visible, activating, hidden }
    public private(set) var phase: Phase = .visible
    public private(set) var generation = 0
    public init() {}
    public mutating func begin() -> Int { generation += 1; phase = .activating; return generation }
    public mutating func finish(_ token: Int, succeeded: Bool) {
        guard generation == token, phase == .activating else { return }
        phase = succeeded ? .hidden : .visible
    }
    public mutating func restore() { generation += 1; phase = .visible }
}
public enum MenuPolicy {
    public static func canHide(_ bundle: String, own: String) -> Bool {
        !bundle.isEmpty && bundle != own && !bundle.hasPrefix("com.apple.")
    }
    public static func allowed(running: Set<String>, hidden: Set<String>, own: String) -> Set<String> {
        running.subtracting(hidden.filter { canHide($0, own: own) }).union([own, "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.TextInputMenuAgent"])
    }
}
public enum PanelLayout {
    // AppKit coordinates, with an arbitrary display origin; no primary-screen assumptions.
    public static func frame(anchor: CGRect, screen: CGRect, requested: CGSize) -> CGRect {
        let inset = screen.insetBy(dx: 8, dy: 8)
        let top = min(inset.maxY, max(inset.minY + 1, anchor.minY - 8))
        let width = min(max(1, requested.width), max(1, inset.width))
        let height = min(max(1, requested.height), max(1, top - inset.minY))
        let x = min(max(anchor.maxX - width, inset.minX), inset.maxX - width)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}

public struct MenuLifetime {
    public private(set) var depth = 0
    public init() {}
    public mutating func opened() { depth += 1 }
    public mutating func closed() -> Bool {
        guard depth > 0 else { return false }
        depth -= 1
        return depth == 0
    }
}
public enum ClickGeometry {
    public static func point(first: CGRect?, current: CGRect?, screen: CGRect, occlusions: [CGRect] = []) -> CGPoint? {
        guard let first, let current, !current.isNull, !current.isInfinite,
              current.width > 2, current.width < 400, current.height > 2, current.height < 80,
              screen.contains(current), current.minY >= screen.minY,
              current.maxY <= screen.minY + 80,
              abs(first.minX - current.minX) < 1, abs(first.minY - current.minY) < 1,
              abs(first.width - current.width) < 1, abs(first.height - current.height) < 1 else { return nil }
        // macOS 27 reports overlapping placeholder frames for notch overflow.
        // Even a stable in-screen rectangle can belong to a concealed item.
        guard !occlusions.contains(where: {
            let overlap = current.intersection($0)
            return !overlap.isNull && overlap.width > 1 && overlap.height > 1
        }) else { return nil }
        return CGPoint(x: current.midX, y: current.midY)
    }
}

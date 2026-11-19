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
    /// MenuBarAgent can give an overflowed status button a zero or off-screen window frame.
    public static func isMenuBarAnchor(_ rect: CGRect, on display: CGRect) -> Bool {
        rect.width > 1 && rect.height > 1 && rect.height < 80
            && rect.midX >= display.minX && rect.midX < display.maxX
            && abs(rect.maxY - display.maxY) <= 16
    }
    public static func clickedAnchor(point: CGPoint, display: CGRect, usable: CGRect, menuBarHeight: CGFloat) -> CGRect? {
        let band = fallbackAnchor(display: display, usable: usable, menuBarHeight: menuBarHeight)
        guard point.x >= display.minX, point.x < display.maxX, point.y >= band.minY, point.y <= display.maxY else { return nil }
        return CGRect(x: point.x - band.width / 2, y: band.minY, width: band.width, height: band.height)
    }
    public static func fallbackAnchor(display: CGRect, usable: CGRect, menuBarHeight: CGFloat) -> CGRect {
        let height = max(1, menuBarHeight)
        return CGRect(x: usable.maxX - 28, y: min(usable.maxY, display.maxY - height), width: 28, height: height)
    }

    // AppKit coordinates, with an arbitrary display origin; no primary-screen assumptions.
    public static func frame(anchor: CGRect, screen: CGRect, requested: CGSize,
                             placement: ShelfPlacement = .anchor, alignment: ShelfAlignment = .left) -> CGRect {
        let inset = screen.insetBy(dx: 8, dy: 8)
        let top = min(inset.maxY, max(inset.minY + 1, anchor.minY - 8))
        let width = min(max(1, requested.width), max(1, inset.width))
        let height = min(max(1, requested.height), max(1, top - inset.minY))
        let desiredX: CGFloat
        switch placement {
        case .anchor:
            switch alignment {
            case .left: desiredX = anchor.maxX - width
            case .center: desiredX = anchor.midX - width / 2
            case .right: desiredX = anchor.minX
            }
        case .left: desiredX = inset.minX
        case .right: desiredX = inset.maxX - width
        }
        let x = min(max(desiredX, inset.minX), inset.maxX - width)
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

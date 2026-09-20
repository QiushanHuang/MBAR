import Foundation
import CoreGraphics
public enum ItemCategory: String, Codable, CaseIterable, Sendable {
    case visible, automatic, always
}
/// Shared shelf order is independent of AX host enumeration, screen origins,
/// and overflow placeholder coordinates. Identity breaks equal-name ties.
public struct ShelfOrderKey: Comparable, Sendable {
    public let name: String
    public let id: String
    public init(name: String, id: String) { self.name = name; self.id = id }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        let identityComparison = lhs.id.localizedStandardCompare(rhs.id)
        return identityComparison == .orderedSame ? lhs.id < rhs.id : identityComparison == .orderedAscending
    }
}
public struct ShelfPolicy: Equatable, Sendable {
    public var assignments: [String: ItemCategory]
    public init(assignments: [String: ItemCategory] = [:], legacySelected: Set<String> = []) {
        self.assignments = assignments
        for bundle in legacySelected where self.assignments[bundle] == nil { self.assignments[bundle] = .automatic }
    }
    public func category(_ bundle: String) -> ItemCategory { assignments[bundle] ?? .visible }
    public var automatic: Set<String> { Set(assignments.filter { $0.value == .automatic }.keys) }
    public var always: Set<String> { Set(assignments.filter { $0.value == .always }.keys) }
    public var hidden: Set<String> { automatic.union(always) }
    public func hiddenWhileCapturing() -> Set<String> { hidden }
    public func hiddenWhileOpening(_ bundle: String) -> Set<String> { hidden.subtracting([bundle]) }
}
public struct SnapshotSession {
    private var generation = 0
    private var active = false
    public init() {}
    public mutating func begin() -> Int { generation += 1; active = true; return generation }
    public mutating func cancel() { generation += 1; active = false }
    public func accepts(_ token: Int) -> Bool { active && token == generation }
}
public enum ShelfMetrics {
    public static let height: CGFloat = 36
    public static func itemWidth(_ size: CGSize?) -> CGFloat {
        guard let size, size.height > 0 else { return 28 }
        return min(320, max(24, size.width * 24 / size.height))
    }
    public static func width(itemWidths: [CGFloat], available: CGFloat, showsLock: Bool = false) -> CGFloat {
        let controls: CGFloat = showsLock ? 72 : 42
        return min(max(36, available), max(controls, itemWidths.reduce(0, +) + CGFloat(itemWidths.count) * 4 + controls))
    }
}
public enum ShelfDismissal {
    public static func isEntryClick(_ point: CGPoint, anchor: CGRect?) -> Bool {
        guard let anchor else { return false }
        return anchor.insetBy(dx: -2, dy: -2).contains(point)
    }
}
public enum SnapshotCrop {
    public static func rect(item: CGRect, display: CGRect, scale: CGFloat) -> CGRect? {
        guard scale > 0, scale.isFinite, item.width > 2, item.width < 400,
              item.height > 2, item.height < 80, display.contains(item),
              item.maxY <= display.minY + 80 else { return nil }
        return CGRect(x: (item.minX - display.minX) * scale, y: (item.minY - display.minY) * scale,
                      width: item.width * scale, height: item.height * scale).integral
    }
}
public struct HostedFrameSample {
    public let frame: CGRect
    public let neighbours: [CGRect]
    public init(frame: CGRect, neighbours: [CGRect]) { self.frame = frame; self.neighbours = neighbours }
}
public enum HostedGeometry {
    public static func resolve(_ samples: [HostedFrameSample], screen: CGRect) -> CGRect? {
        var eligible: [CGRect] = []
        for sample in samples {
            if ClickGeometry.point(first: sample.frame, current: sample.frame, screen: screen, occlusions: sample.neighbours) != nil,
               !eligible.contains(sample.frame) { eligible.append(sample.frame) }
        }
        return eligible.count == 1 ? eligible[0] : nil
    }
}

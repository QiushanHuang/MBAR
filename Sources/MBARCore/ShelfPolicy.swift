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
public enum ShelfStyle: String, CaseIterable, Sendable { case strip, grid, list }
public enum ShelfPlacement: String, CaseIterable, Sendable { case anchor, left, right }
public enum ShelfAlignment: String, CaseIterable, Sendable { case left, center, right }
public enum ShelfToolsSide: String, CaseIterable, Sendable { case left, right }

public enum ShelfIconScale {
    public static let range = 0.70...1.50
    private static let incrementsPerUnit = 20.0
    public static let step = 1 / incrementsPerUnit

    public static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        return (clamped * incrementsPerUnit).rounded() / incrementsPerUnit
    }
}

public enum ShelfMetrics {
    /// Outer curvature of the reference glass shelf, shared by the strip, grid and list.
    public static func cornerRadius(for size: CGSize) -> CGFloat {
        max(0, min(16, min(size.width, size.height) / 2))
    }

    public static let referenceIconHeight: CGFloat = 18
    public static let standardGlyphHeightLimit: CGFloat = 24
    public static let stripInset: CGFloat = 8
    public static let height: CGFloat = 36
    public static let tileHeight: CGFloat = 56
    public static let listRowHeight: CGFloat = 36
    public static let rowSpacing: CGFloat = 4
    public static let bodyInset: CGFloat = 6
    public static let footerHeight: CGFloat = 34

    public static func gridColumns(for width: CGFloat, itemCount: Int) -> Int {
        let fitting = Int((width - 2 * bodyInset + rowSpacing) / (84 + rowSpacing))
        return max(1, min(4, itemCount, fitting))
    }

    /// Source images carry logical point dimensions before user scaling. Unknown artwork
    /// is fitted to an 18pt reference at load time. Measured captures can use the
    /// full menu-bar height: layout reserves additional space for them below.
    public static func glyphSize(_ source: CGSize?, scale: Double = 1) -> CGSize {
        let reference = CGSize(width: referenceIconHeight, height: referenceIconHeight)
        let size = source.flatMap { $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 ? $0 : nil } ?? reference
        let userScale = ShelfIconScale.normalized(scale)
        let factor = min(userScale * min(1, 80 / size.height), 316 / size.width)
        return CGSize(width: size.width * factor, height: size.height * factor)
    }

    private static func extraHeight(scale: Double, tallestGlyphHeight: CGFloat?) -> CGFloat {
        let glyphHeight = tallestGlyphHeight ?? standardGlyphHeightLimit * ShelfIconScale.normalized(scale)
        return max(0, ceil(glyphHeight) - standardGlyphHeightLimit)
    }

    public static func stripItemHeight(scale: Double, tallestGlyphHeight: CGFloat? = nil) -> CGFloat {
        28 + extraHeight(scale: scale, tallestGlyphHeight: tallestGlyphHeight)
    }
    public static func tileHeight(scale: Double, tallestGlyphHeight: CGFloat? = nil) -> CGFloat {
        tileHeight + extraHeight(scale: scale, tallestGlyphHeight: tallestGlyphHeight)
    }
    public static func listRowHeight(scale: Double, tallestGlyphHeight: CGFloat? = nil) -> CGFloat {
        listRowHeight + extraHeight(scale: scale, tallestGlyphHeight: tallestGlyphHeight)
    }

    public static func size(style: ShelfStyle, itemWidths: [CGFloat], available: CGSize, showsLock: Bool,
                            scale: Double = 1, tallestGlyphHeight: CGFloat? = nil) -> CGSize {
        let count = itemWidths.count
        let maxWidth = max(1, available.width)
        let maxHeight = max(1, available.height)
        if style == .strip {
            let ideal = count == 0 ? 190 : width(itemWidths: itemWidths, available: maxWidth, showsLock: showsLock)
            return CGSize(width: min(ideal, maxWidth), height: min(height + extraHeight(scale: scale, tallestGlyphHeight: tallestGlyphHeight), maxHeight))
        }
        let columns = CGFloat(max(1, min(count, 4)))
        let ideal = style == .list ? 264 : max(208, 2 * bodyInset + columns * 92 + (columns - 1) * rowSpacing)
        let width = min(ideal, maxWidth)
        let fittedColumns = style == .list ? 1 : gridColumns(for: width, itemCount: count)
        let rows = max(1, (count + fittedColumns - 1) / fittedColumns)
        let visibleRows = CGFloat(min(rows, style == .list ? 8 : 4))
        let rowHeight = style == .list ? listRowHeight(scale: scale, tallestGlyphHeight: tallestGlyphHeight)
                                      : tileHeight(scale: scale, tallestGlyphHeight: tallestGlyphHeight)
        let height = 2 * bodyInset + visibleRows * rowHeight + (visibleRows - 1) * rowSpacing + footerHeight
        return CGSize(width: width, height: min(height, maxHeight))
    }
    public static func itemWidth(_ size: CGSize?, scale: Double = 1) -> CGFloat {
        max(24, ceil(glyphSize(size, scale: scale).width) + 4)
    }
    public static func width(itemWidths: [CGFloat], available: CGFloat, showsLock: Bool = false) -> CGFloat {
        let controls: CGFloat = 2 * stripInset + (showsLock ? 64 : 34)
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

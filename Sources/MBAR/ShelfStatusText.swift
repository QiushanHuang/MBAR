import AppKit
import ApplicationServices

@MainActor final class ShelfStatusText {
    static let bundleID = "io.github.clash-verge-rev.clash-verge-rev"
    static let sourceDescription = "Clash Verge Rev · 辅助功能实时网速"

    func samples(for items: [MenuItem], library: IconLibrary) async -> [String: ShelfLiveImage] {
        let candidates = items.filter { $0.bundle == Self.bundleID }
        guard candidates.count == 1, let item = candidates.first,
              let glyph = library.verifiedStatusGlyph(for: item), !Task.isCancelled else { return [:] }

        let title = await Task.detached(priority: .utility) {
            Self.currentTitle(of: item)
        }.value
        guard !Task.isCancelled, let title, library.verifiedStatusGlyph(for: item) === glyph else { return [:] }
        let lines = Self.rateLines(title)
        guard !lines.isEmpty else { return [:] }
        return [item.id: ShelfLiveImage(Self.render(glyph, lines: lines), item: item,
                                       source: Self.sourceDescription, value: lines.joined(separator: "，"))]
    }

    /// Recheck only this app and its sole status item. Treat disappearance, replacement
    /// (including a new element at the old index), and an unreadable AX title as unavailable.
    private nonisolated static func currentTitle(of item: MenuItem) -> String? {
        guard AXIsProcessTrusted(),
              let process = NSRunningApplication(processIdentifier: item.pid),
              process.bundleIdentifier == item.bundle, !process.isTerminated else { return nil }
        let root = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let bar = MenuDiscovery.attribute(root, kAXExtrasMenuBarAttribute),
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        let extras = bar as! AXUIElement
        AXUIElementSetMessagingTimeout(extras, 0.15)
        let children = MenuDiscovery.children(extras)
        guard children.count == 1, let leaf = children.first, CFEqual(leaf, item.element) else { return nil }
        AXUIElementSetMessagingTimeout(leaf, 0.15)
        return MenuDiscovery.attribute(leaf, kAXTitleAttribute) as? String
    }

    static func rateLines(_ title: String) -> [String] {
        guard title.utf8.count <= 96 else { return [] }
        let lines = title.split(whereSeparator: { $0 == "|" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard (1...2).contains(lines.count) else { return [] }
        let rate = #"^(?:[↑↓⬆⬇▲▼]\s*)?[0-9]{1,8}(?:[.,][0-9]{1,3})?\s*(?:[KMGT](?:i?B)?|B)/s$"#
        return lines.allSatisfy { $0.range(of: rate, options: .regularExpression) != nil } ? lines : []
    }

    static func render(_ icon: NSImage, lines: [String]) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.black
        ]
        let width = ceil(lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0)
        let size = NSSize(width: icon.size.width + 4 + width, height: 24)
        let output = NSImage(size: size, flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: (size.height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            for (index, line) in lines.enumerated() {
                let y: CGFloat = lines.count == 1 ? 6 : (index == 0 ? 12 : 1)
                (line as NSString).draw(at: NSPoint(x: icon.size.width + 4, y: y), withAttributes: attributes)
            }
            return true
        }
        output.isTemplate = true
        return output
    }
}

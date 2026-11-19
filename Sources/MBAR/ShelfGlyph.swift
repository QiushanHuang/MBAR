import AppKit
import MBARCore
import SwiftUI

/// Clear glass can cross a dark window and a white one in the same row. Keep
/// template ink bright and give original artwork a narrow, shape-local light
/// edge. The material's dark contour supplies the other side of the contrast.
struct ShelfGlyph: View {
    private let image: NSImage?
    private let symbol: String
    private let onClearGlass: Bool
    private let selected: Bool
    private let preservesOriginalInk: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(image: NSImage?, onClearGlass: Bool, preservesOriginalInk: Bool = false) {
        self.image = image
        self.onClearGlass = onClearGlass
        self.preservesOriginalInk = preservesOriginalInk
        symbol = "circle.dotted"
        selected = false
    }

    init(systemName: String, onClearGlass: Bool, selected: Bool = false) {
        image = nil
        symbol = systemName
        self.onClearGlass = onClearGlass
        self.selected = selected
        preservesOriginalInk = false
    }

    var body: some View {
        let clear = onClearGlass && !reduceTransparency
        if let image {
            let template = image.isTemplate || (clear && !preservesOriginalInk && Self.usesSingleInk(image))
            let source = Image(nsImage: image)
            source.renderingMode(template ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(clear ? Color.white : Color.primary)
                .modifier(GlyphContour(source: source, ink: template ? .black : .white, enabled: clear))
        } else {
            let source = Image(systemName: symbol)
            source
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(clear ? Color.white : (selected ? Color.accentColor : Color.secondary))
                .modifier(GlyphContour(source: source, ink: .black, enabled: clear))
        }
    }

    @MainActor private static let inkCache = NSMapTable<NSImage, NSNumber>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)

    @MainActor static func usesSingleInk(_ image: NSImage) -> Bool {
        if let result = inkCache.object(forKey: image) { return result.boolValue }
        let result = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            .map(IconInkProfile.isTemplateCandidate) ?? false
        inkCache.setObject(NSNumber(value: result), forKey: image)
        return result
    }
}

/// The stroke follows the alpha silhouette even inside open letters and rings.
/// Drawing it behind the source keeps the glyph dimensions and original opaque colors intact.
private struct GlyphContour: ViewModifier {
    let source: Image
    let ink: Color
    let enabled: Bool

    func body(content: Content) -> some View {
        content.background {
            if enabled {
                Canvas { context, size in
                    var silhouette = context.resolve(source.renderingMode(.template))
                    silhouette.shading = .color(ink.opacity(0.95))
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                    for delta in [CGPoint(x: -0.8, y: 0), CGPoint(x: 0.8, y: 0),
                                  CGPoint(x: 0, y: -0.8), CGPoint(x: 0, y: 0.8)] {
                        context.draw(silhouette, in: rect.offsetBy(dx: delta.x, dy: delta.y))
                    }
                }
                .padding(-1)
            }
        }
    }
}

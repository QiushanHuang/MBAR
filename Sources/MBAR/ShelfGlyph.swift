import AppKit
import MBARCore
import SwiftUI

/// Paint the source exactly once. Some tray drawings encode their eyes, fine lines,
/// and inactive dots entirely in alpha, including intermediate coverage.
struct ShelfGlyph: View {
    private let image: NSImage?
    private let symbol: String
    private let onClearGlass: Bool
    private let treatment: ShelfIconTreatment
    private let selected: Bool
    private let preservesOriginalInk: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(image: NSImage?, onClearGlass: Bool, treatment: ShelfIconTreatment = .automatic,
         preservesOriginalInk: Bool = false) {
        self.image = image
        self.onClearGlass = onClearGlass
        self.treatment = treatment
        self.preservesOriginalInk = preservesOriginalInk
        symbol = "circle.dotted"
        selected = false
    }

    init(systemName: String, onClearGlass: Bool, treatment: ShelfIconTreatment = .automatic, selected: Bool = false) {
        image = nil
        symbol = systemName
        self.onClearGlass = onClearGlass
        self.treatment = treatment
        self.selected = selected
        preservesOriginalInk = false
    }

    var body: some View {
        let template = image.map {
            $0.isTemplate || (onClearGlass && (!reduceTransparency || treatment != .automatic) && !preservesOriginalInk && Self.usesSingleInk($0))
        } ?? true
        let source = image.map(Image.init(nsImage:)) ?? Image(systemName: symbol)
        let glyph = source.renderingMode(template ? .template : .original)
            .resizable().interpolation(.high).scaledToFit()
        if template {
            glyph.shelfInk(clearGlass: onClearGlass, treatment: treatment,
                           secondary: image == nil && !onClearGlass, selected: selected)
        } else if onClearGlass && !reduceTransparency, let image {
            // Preserve original RGB; only the edge needs separation from a like-colored background.
            let dark = Self.analysis(of: image).darkArtwork
            glyph.shadow(color: (dark ? Color.white : Color.black).opacity(contrast == .increased ? 1 : 0.85),
                         radius: 0.85, y: 0.5)
        } else {
            glyph
        }
    }

    private final class ArtworkAnalysis: NSObject {
        let singleInk: Bool
        let darkArtwork: Bool

        init(_ image: NSImage) {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                singleInk = false
                darkArtwork = true
                return
            }
            singleInk = IconInkProfile.isTemplateCandidate(cg)
            // Area-average premultiplied RGBA without flattening onto black.
            // This swatch only selects the shadow; source pixels are never modified.
            let side = 24
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            darkArtwork = pixels.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
                else { return true }
                ctx.interpolationQuality = .high
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
                let bytes = buffer.bindMemory(to: UInt8.self)
                var intensity = 0, coverage = 0
                for i in stride(from: 0, to: bytes.count, by: 4) {
                    intensity += 21 * Int(bytes[i]) + 72 * Int(bytes[i + 1]) + 7 * Int(bytes[i + 2])
                    coverage += Int(bytes[i + 3])
                }
                return intensity < 48 * coverage
            }
        }
    }

    @MainActor private static let cache = NSMapTable<NSImage, ArtworkAnalysis>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)

    @MainActor private static func analysis(of image: NSImage) -> ArtworkAnalysis {
        if let cached = cache.object(forKey: image) { return cached }
        let entry = ArtworkAnalysis(image)
        cache.setObject(entry, forKey: image)
        return entry
    }

    @MainActor static func usesSingleInk(_ image: NSImage) -> Bool { analysis(of: image).singleInk }
}

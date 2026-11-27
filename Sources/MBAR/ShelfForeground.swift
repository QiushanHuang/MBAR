import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import MBARCore

private struct CollectsInk: EnvironmentKey { static let defaultValue = false }
private struct ScrollingInk: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var collectsShelfInk: Bool {
        get { self[CollectsInk.self] }
        set { self[CollectsInk.self] = newValue }
    }
    var scrollingShelfInk: Bool {
        get { self[ScrollingInk.self] }
        set { self[ScrollingInk.self] = newValue }
    }
}

private enum InkRegion {
    case artwork(Anchor<CGRect>, AnyView, scrolling: Bool)
    case viewport(Anchor<CGRect>)
}

private struct ShelfInkRegions: PreferenceKey {
    static var defaultValue: [InkRegion] { [] }
    static func reduce(value: inout [InkRegion], nextValue: () -> [InkRegion]) {
        value.append(contentsOf: nextValue())
    }
}

/// Reduce the live material to one luminance sample per *whole* symbol or
/// label. Only its original alpha mask determines the shape of the final ink.
@available(macOS 26, *)
private struct MaterialInkField: NSViewRepresentable {
    let size: CGSize
    var keyline = false
    @Environment(\.displayScale) private var displayScale

    final class InkView: NSGlassEffectView {
        private var sampleSize: CGSize = .zero
        private var samplesKeyline = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        // Opposite ink for the rim; alpha is zero on uniform backgrounds
        // and ramps up when both light and dark occupy the sampled region.
        private static let levels = 16
        private static let edgePalette: Data = {
            let ramp: [Float] = (0..<levels).flatMap { i in
                let fraction = Float(i) / Float(levels - 1)
                let alpha = min(1, min(fraction, 1 - fraction) * 6)
                let channel: Float = i * 2 < levels ? 0 : alpha
                return [channel, channel, channel, alpha]
            }
            // The input is grayscale. Replicate the 1D ramp across G and B.
            let rgba = Array(repeating: ramp, count: levels * levels).flatMap { $0 }
            return rgba.withUnsafeBytes { Data($0) }
        }()

        func sample(_ size: CGSize, keyline: Bool) {
            guard size.width > 0, size.height > 0, sampleSize != size || samplesKeyline != keyline else { return }
            sampleSize = size
            samplesKeyline = keyline
            let extent = CGRect(origin: .zero, size: size)
            let average = CIFilter.areaAverage()
            average.extent = extent
            // CIAreaAverage yields one texel. Extend that texel before deciding
            // polarity so a background boundary cannot run through the artwork.
            let extend = CIFilter.affineClamp()
            let crop = CIFilter(name: "CICrop")!
            crop.setValue(CIVector(cgRect: extent), forKey: "inputRectangle")
            let luma = CIFilter.colorMatrix()
            let weights = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            luma.rVector = weights
            luma.gVector = weights
            luma.bVector = weights
            let threshold = CIFilter.colorThreshold()
            threshold.threshold = 0.16
            let sampling = [luma, threshold, average, extend, crop] as [CIFilter]
            if keyline {
                let edge = CIFilter.colorCube()
                edge.cubeDimension = Float(Self.levels)
                edge.cubeData = Self.edgePalette
                contentFilters = sampling + [edge]
            } else {
                let majority = CIFilter.colorThreshold()
                majority.threshold = 0.5
                contentFilters = sampling + [majority, CIFilter.colorInvert()]
            }
        }
    }

    func makeNSView(context: Context) -> InkView {
        let field = InkView()
        field.style = .clear
        field.cornerRadius = 0
        field.contentView = NSView()
        field.appearance = NSAppearance(named: .darkAqua)
        field.setAccessibilityElement(false)
        return field
    }
    func updateNSView(_ view: InkView, context: Context) {
        view.sample(CGSize(width: ceil(size.width * displayScale), height: ceil(size.height * displayScale)), keyline: keyline)
    }
}

extension View {
    /// Only visible ink regions sample the backdrop. Native buttons,
    /// full-color artwork and hit testing stay in their normal view hierarchy.
    func shelfInkSurface(clearGlass: Bool, treatment: ShelfIconTreatment) -> some View {
        modifier(ShelfInkSurface(clearGlass: clearGlass, treatment: treatment))
    }

    /// Resolve scroll bounds alongside the glyph anchors, so out-of-view rows
    /// cannot paint into the fixed toolbar or the footer.
    func shelfInkViewport() -> some View {
        environment(\.scrollingShelfInk, true)
            .transformAnchorPreference(key: ShelfInkRegions.self, value: .bounds) { regions, bounds in
                regions.append(.viewport(bounds))
            }
    }

    func shelfInk(clearGlass: Bool, treatment: ShelfIconTreatment,
                  secondary: Bool = false, selected: Bool = false) -> some View {
        ShelfInk(content: self, clearGlass: clearGlass, treatment: treatment, secondary: secondary, selected: selected)
    }
}

private struct ShelfInk<Shape: View>: View {
    let content: Shape
    let clearGlass: Bool
    let treatment: ShelfIconTreatment
    let secondary: Bool
    let selected: Bool
    @Environment(\.collectsShelfInk) private var collects
    @Environment(\.scrollingShelfInk) private var scrolling
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if clearGlass && !reduced && collects && treatment == .automatic {
            // A clear foreground keeps a single layout and its accessible labels.
            content.foregroundStyle(Color.clear)
                .anchorPreference(key: ShelfInkRegions.self, value: .bounds) { anchor in
                    [.artwork(anchor, AnyView(content.foregroundStyle(.white)
                        .opacity(secondary && contrast != .increased ? 0.91 : 1)), scrolling: scrolling)]
                }
        } else if clearGlass && treatment != .automatic {
            let dark = treatment == .darkInk || (treatment == .system && scheme == .light)
            content.foregroundStyle(dark ? Color.black : Color.white)
                .opacity(secondary && contrast != .increased ? 0.86 : 1)
                .shadow(color: (dark ? Color.white : Color.black).opacity(0.85), radius: 0.85, y: 0.5)
        } else {
            content.foregroundStyle(selected ? Color.accentColor : (secondary ? Color.secondary : Color.primary))
        }
    }
}

private struct ShelfInkSurface: ViewModifier {
    let clearGlass: Bool
    let treatment: ShelfIconTreatment
    @Environment(\.accessibilityReduceTransparency) private var reduced

    func body(content: Content) -> some View {
        let enabled: Bool
        if #available(macOS 26, *) { enabled = clearGlass && !reduced && treatment == .automatic }
        else { enabled = false }
        return content
            .environment(\.collectsShelfInk, enabled)
            .overlayPreferenceValue(ShelfInkRegions.self) { regions in
                if #available(macOS 26, *), enabled, !regions.isEmpty {
                    GeometryReader { proxy in
                        let panel = CGRect(origin: .zero, size: proxy.size)
                        let viewport = regions.compactMap { region -> CGRect? in
                            if case let .viewport(anchor) = region { return proxy[anchor].intersection(panel) }
                            return nil
                        }.first ?? panel
                        ZStack(alignment: .topLeading) {
                            ForEach(regions.indices, id: \.self) { index in
                                if case let .artwork(anchor, artwork, scrolling) = regions[index] {
                                    let frame = proxy[anchor]
                                    let visible = frame.intersection(scrolling ? viewport : panel)
                                    if !visible.isEmpty {
                                        let shape = artwork.frame(width: frame.width, height: frame.height)
                                            .offset(x: frame.minX - visible.minX, y: frame.minY - visible.minY)
                                            .frame(width: visible.width, height: visible.height, alignment: .topLeading)
                                            .clipped()
                                        ZStack {
                                            // Subtract the original drawing from the feathered
                                            // silhouette. Only its faint perimeter can add contrast.
                                            MaterialInkField(size: visible.size, keyline: true)
                                                .mask {
                                                    ZStack {
                                                        shape.blur(radius: 1.1)
                                                        shape.blendMode(.destinationOut)
                                                    }.compositingGroup()
                                                }
                                            MaterialInkField(size: visible.size)
                                                .mask { shape }
                                        }
                                        .frame(width: visible.width, height: visible.height)
                                        .clipped()
                                        .position(x: visible.midX, y: visible.midY)
                                    }
                                }
                            }
                        }
                        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

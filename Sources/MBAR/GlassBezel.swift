import AppKit

/// Spatially weights AppKit's live refractive material and adds a directional surface reflection.
/// The normal/light key and counter-lobe principle is described in:
/// https://github.com/shayann07/liquidglass/blob/9effb52bcb9d36e8048666b935f9d4ac46b99b47/ports/npm/optics.mjs#L174-L197
@MainActor final class GlassBezel {
    let materialMask = CALayer()
    let highlight = CALayer()

    private var drawnRadius: CGFloat = -1
    private var drawnScale: CGFloat = 0

    func layout(in bounds: CGRect, cornerRadius: CGFloat, scale: CGFloat, centerAmount: CGFloat) {
        let scale = max(1, scale)
        // A nine-slice tile carries four curved corners and one stretchable center pixel.
        // Give the tile room even if a very small panel is narrower than two corner radii.
        let maxCap = max(0, (floor(min(bounds.width, bounds.height) * scale) - 1) / 2)
        let radius = min(max(0, cornerRadius), floor(maxCap) / scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        materialMask.frame = bounds
        highlight.frame = bounds
        materialMask.backgroundColor = CGColor(gray: 1, alpha: min(1, max(0, centerAmount)))
        materialMask.cornerRadius = radius
        materialMask.masksToBounds = true
        guard radius != drawnRadius || scale != drawnScale else { return }

        let cap = Int(ceil(radius * scale))
        let side = 2 * cap + 1
        let center = CGRect(x: CGFloat(cap) / CGFloat(side), y: CGFloat(cap) / CGFloat(side),
                            width: 1 / CGFloat(side), height: 1 / CGFloat(side))
        for layer in [materialMask, highlight] {
            layer.contentsScale = scale
            layer.contentsCenter = center
            layer.contentsGravity = .resize
        }
        let tiles = Self.renderTiles(side: side, scale: scale, radius: radius)
        materialMask.contents = tiles.mask
        highlight.contents = tiles.light
        drawnRadius = radius
        drawnScale = scale
    }

    private static func renderTiles(side: Int, scale: CGFloat, radius: CGFloat) -> (mask: CGImage?, light: CGImage?) {
        var mask = [UInt8](repeating: 0, count: side * side * 4)
        var light = mask
        let halfSide = CGFloat(side) / (2 * scale)
        let bevel = max(1 / scale, radius * 0.38)

        for y in 0..<side {
            for x in 0..<side {
                let dx = (CGFloat(x) + 0.5) / scale - halfSide
                let dy = (CGFloat(y) + 0.5) / scale - halfSide
                let qx = abs(dx) - halfSide + radius
                let qy = abs(dy) - halfSide + radius
                let arcLength = hypot(max(0, qx), max(0, qy))
                let depth = radius - arcLength - min(0, max(qx, qy))
                let coverage = min(1, max(0, 0.5 + depth * scale))
                guard coverage > 0, depth < bevel, radius > 0 else { continue }

                let u = min(1, max(0, depth / bevel))
                let shoulder = 1 - u * u * (3 - 2 * u)
                let offset = (y * side + x) * 4
                let strength = byte(coverage * shoulder)
                for channel in 0..<4 { mask[offset + channel] = strength }

                // The straight sections' normals do not change as the shelf grows.
                // Image rows run top to bottom; the key light is above and to the left.
                let nx: CGFloat
                let ny: CGFloat
                if arcLength > 0 {
                    nx = max(0, qx) / arcLength
                    ny = max(0, qy) / arcLength
                } else {
                    nx = qx > qy ? 1 : 0
                    ny = qx > qy ? 0 : 1
                }
                let facing = (dx < 0 ? nx : -nx) * 0.48 + (dy < 0 ? ny : -ny) * 0.877
                let key = pow(max(0, facing), 5)
                let counter = pow(max(0, -facing), 7)
                let ridge = exp(-pow((u - 0.15) / 0.16, 2))
                let reflection = coverage * (0.35 * key + 0.13 * counter) * ridge
                let shadedSlope = coverage * 0.09 * (1 - key) * exp(-pow((u - 0.38) / 0.21, 2))
                let luminance = byte(reflection)
                light[offset] = luminance
                light[offset + 1] = luminance
                light[offset + 2] = luminance
                light[offset + 3] = byte(reflection + (1 - reflection) * shadedSlope)
            }
        }
        return (image(mask, side: side), image(light, side: side))
    }

    private static func byte(_ value: CGFloat) -> UInt8 {
        UInt8((255 * min(1, max(0, value))).rounded())
    }

    private static func image(_ pixels: [UInt8], side: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

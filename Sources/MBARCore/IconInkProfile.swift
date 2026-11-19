import CoreGraphics

/// A template can preserve opacity, but it cannot preserve color or differences
/// between solid light and dark ink. Inspect unpremultiplied channels accordingly.
public struct IconInkProfile {
    private var hasTransparency = false
    private var neutral = true
    private var darkest = 255
    private var lightest = 0

    public init() {}

    public mutating func observe(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        if alpha < 16 {
            hasTransparency = true
            return
        }
        guard alpha >= 48, neutral else { return }
        let low = Int(min(red, green, blue)) * 255 / Int(alpha)
        let high = Int(max(red, green, blue)) * 255 / Int(alpha)
        neutral = high - low <= 12
        darkest = min(darkest, low)
        lightest = max(lightest, high)
    }

    public var isTemplateCandidate: Bool {
        hasTransparency && neutral && darkest <= lightest && lightest - darkest <= 24
    }

    /// Very large originals keep their own colors; classification never samples
    /// away a small colored badge or resizes an icon to guess its ink.
    public static func isTemplateCandidate(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              width * height <= 256 * 1024,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var profile = IconInkProfile()
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            profile.observe(red: pixels[i], green: pixels[i + 1], blue: pixels[i + 2], alpha: pixels[i + 3])
            if !profile.neutral || profile.lightest - profile.darkest > 24 { return false }
        }
        return profile.isTemplateCandidate
    }
}

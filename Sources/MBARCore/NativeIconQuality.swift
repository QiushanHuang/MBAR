import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct PreparedNativeIcon: Sendable {
    public let image: IconDecodedImage
    public let mode: IconDisplayMode
}
public enum NativeIconQuality {
    /// Require transparent padding on every edge. Empty, clipped, background-only and heavily faded crops fail closed.
    public static func prepare(_ image: CGImage) -> PreparedNativeIcon? {
        let width = image.width, height = image.height
        guard width >= 6, height >= 6, width <= 1600, height <= 320,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1, maxAlpha: UInt8 = 0, count = 0
        var monochrome = true
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4, alpha = pixels[i + 3]
            maxAlpha = max(maxAlpha, alpha)
            if alpha > 16 {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y); count += 1
                let high = max(pixels[i], pixels[i + 1], pixels[i + 2]), low = min(pixels[i], pixels[i + 1], pixels[i + 2])
                if Int(high) - Int(low) > max(8, Int(alpha) / 12) { monochrome = false }
            }
        }}
        guard count >= 8, count < width * height * 9 / 10, maxAlpha >= 160,
              minX >= 2, minY >= 2, maxX < width - 2, maxY < height - 2 else { return nil }
        let rect = CGRect(x: minX - 1, y: minY - 1, width: maxX - minX + 3, height: maxY - minY + 3)
        // Crop the normalized bitmap whose rows were inspected, keeping the coordinate convention consistent.
        guard let normalized = context.makeImage(), let trimmed = normalized.cropping(to: rect) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, trimmed, nil)
        guard CGImageDestinationFinalize(destination), let decoded = IconImageDecoder.decode(data as Data, path: "native.png") else { return nil }
        return PreparedNativeIcon(image: decoded, mode: monochrome ? .template : .original)
    }
}

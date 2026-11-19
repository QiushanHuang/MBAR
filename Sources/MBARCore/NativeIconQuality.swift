import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct PreparedNativeIcon: Sendable {
    public let image: IconDecodedImage
    public let mode: IconDisplayMode
    public let pointSize: CGSize?
}
public enum NativeIconQuality {
    /// Require transparent padding on every edge. Empty, clipped, background-only and heavily faded crops fail closed.
    public static func prepare(_ image: CGImage, sourcePointSize: CGSize? = nil) -> PreparedNativeIcon? {
        let width = image.width, height = image.height
        guard width >= 6, height >= 6, width <= 1600, height <= 320,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1, maxAlpha: UInt8 = 0, count = 0
        var ink = IconInkProfile()
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4, alpha = pixels[i + 3]
            ink.observe(red: pixels[i], green: pixels[i + 1], blue: pixels[i + 2], alpha: alpha)
            maxAlpha = max(maxAlpha, alpha)
            if alpha > 16 {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y); count += 1
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
        guard CGImageDestinationFinalize(destination), let decoded = IconImageDecoder.decode(data as Data, path: "native.png", maximumPixelSize: 1600) else { return nil }
        // Recover logical dimensions before the original transparent cell padding
        // is discarded. A Retina pixel is only half a menu-bar point.
        let pointSize = sourcePointSize.flatMap { points -> CGSize? in
            guard points.width.isFinite, points.width > 0, points.height.isFinite, points.height > 0 else { return nil }
            let pointsPerPixel = points.height / CGFloat(height)
            return CGSize(width: rect.width * pointsPerPixel, height: rect.height * pointsPerPixel)
        }
        return PreparedNativeIcon(image: decoded, mode: ink.isTemplateCandidate ? .template : .original, pointSize: pointSize)
    }
}

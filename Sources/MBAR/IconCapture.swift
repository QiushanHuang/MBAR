import AppKit
import ScreenCaptureKit
import MBARCore

struct CapturedIcons {
    var images: [String: NSImage]
    var failure: String?
    var error: Error? = nil
}
// A still of the menu bar only: no desktop/windows, audio, recording stream or files.
@MainActor final class IconCapture {
    func capture(_ items: [MenuItem]) async -> CapturedIcons {
        do {
          return try await ScreenCaptureAccess.shared.perform {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            var output: [String: NSImage] = [:]
            var geometry: [String] = []
            for display in content.displays {
                try Task.checkCancellation()
                let relevant = items.filter { item in
                    guard let frame = item.frame else { return false }
                    return SnapshotCrop.rect(item: frame, display: display.frame, scale: 1) != nil
                }
                guard !relevant.isEmpty else { continue }
                // Apple's menu-bar capture filter excludes the wallpaper and app
                // windows, preserving transparency behind the actual status glyphs.
                let filter = SCContentFilter(display: display, including: [SCWindow]())
                if #available(macOS 14.2, *) { filter.includeMenuBar = true }
                let scale = CGFloat(filter.pointPixelScale)
                let height = relevant.compactMap(\.frame).map { $0.maxY - display.frame.minY }.max() ?? 33
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: 0, y: 0, width: display.frame.width, height: height)
                config.width = Int(display.frame.width * scale)
                config.height = Int(height * scale)
                config.showsCursor = false; config.capturesAudio = false
                // ScreenCaptureKit defaults to a clear background.
                config.shouldBeOpaque = false
                config.ignoreShadowsDisplay = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                try Task.checkCancellation()
                geometry.append("display=\(display.frame) scale=\(scale) strip=\(config.sourceRect) image=\(image.width)x\(image.height) items=\(relevant.count)")
                for item in relevant {
                    guard let frame = item.frame,
                          let crop = SnapshotCrop.rect(item: frame, display: display.frame, scale: scale),
                          CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(crop),
                          let cg = image.cropping(to: crop), Self.hasPixels(cg) else { continue }
                    output[item.id] = NSImage(cgImage: cg, size: frame.size)
                }
            }
            UserDefaults.standard.set(geometry, forKey: "lastCaptureGeometry")
            return CapturedIcons(images: output, failure: output.isEmpty && !items.isEmpty ? "系统没有返回可用图标快照，请刷新后重试。" : nil)
          }
        } catch is CancellationError { return .init(images: [:], failure: nil) }
        catch { return .init(images: [:], failure: "无法读取菜单栏快照：\(error.localizedDescription)", error: error) }
    }
    private static func hasPixels(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let ctx = CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8,
                                      bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 24 }
        }
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import MBAR

final class ShelfInkDetailTests: XCTestCase {
    @MainActor func testClearGlassPreservesNarrowOpeningsAndPartialCoverage() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Requires transparent desktop material")
        }
        let size = CGSize(width: 30, height: 12)
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 60, height: 24, bitsPerComponent: 8,
                                             bytesPerRow: 240, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.scaleBy(x: 2, y: 2)
        // A cutout in a single-ink status icon and three status indicators whose
        // relative alpha (rather than their shape or RGB) conveys their state.
        bitmap.setFillColor(gray: 0, alpha: 1)
        bitmap.fill(CGRect(x: 1, y: 2, width: 8, height: 8))
        bitmap.clear(CGRect(x: 4, y: 4, width: 1, height: 4))
        for (x, alpha): (CGFloat, CGFloat) in [(10, 0.25), (16, 0.55), (22, 1)] {
            bitmap.setFillColor(gray: 0, alpha: alpha)
            bitmap.fill(CGRect(x: x, y: 3, width: 4, height: 6))
        }
        let source = NSImage(cgImage: try XCTUnwrap(bitmap.makeImage()), size: size)
        source.isTemplate = true

        let view = ShelfGlyph(image: source, onClearGlass: true)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.12))
        let host = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let rendered = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 24,
                                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rendered.size = size
        host.cacheDisplay(in: host.bounds, to: rendered)
        func luma(_ x: Int, _ y: Int = 12) throws -> CGFloat {
            let c = try XCTUnwrap(rendered.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        }
        let paper = try luma(56), ink = try luma(47)
        XCTAssertGreaterThan(abs(ink - paper), 0.35, "The foreground needs visible contrast against its local backing.")
        func coverage(_ x: Int) throws -> CGFloat { (try luma(x) - paper) / (ink - paper) }
        XCTAssertEqual(try coverage(8), 0, accuracy: 0.04, "The one-point opening must remain open.")
        XCTAssertEqual(try coverage(23), 0.25, accuracy: 0.04, "The faint status indicator must retain its lower coverage.")
        XCTAssertEqual(try coverage(35), 0.55, accuracy: 0.04, "The middle indicator must remain distinct from solid ink.")
    }
}

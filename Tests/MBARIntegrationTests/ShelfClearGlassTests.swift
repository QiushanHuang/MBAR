import AppKit
import MBARCore
import XCTest
@testable import MBAR

final class ShelfClearGlassTests: XCTestCase {
    @MainActor func testUntintedGlassLeavesItsInteriorUnpaintedAndKeepsANativeRim() throws {
        guard #available(macOS 26, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Checking clear glass requires the native transparent material.")
        }
        let size = CGSize(width: 212, height: 38)
        let window = NSPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        var appearance = ShelfAppearance(material: .appleGlass, tint: .init(red: 1, green: 0, blue: 0), intensity: 0, frostAmount: 0)
        let content = NSView()
        let backdrop = ShelfBackdrop(frame: .init(origin: .zero, size: size), configuration: appearance, content: content)
        window.contentView = backdrop
        backdrop.layoutSubtreeIfNeeded()
        let optics = try XCTUnwrap(backdrop.subviews.first as? ClearShelfGlass)
        let glass = optics.glass
        let mask = try XCTUnwrap(glass.layer?.mask)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                          bitsPerComponent: 8, bytesPerRow: 4 * Int(size.width), space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        let bytes = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            ctx.clear(CGRect(origin: .zero, size: size))
            mask.render(in: ctx)
            return bytes[y * ctx.bytesPerRow + x * 4 + 3]
        }
        XCTAssertGreaterThan((0..<4).map { alpha(106, $0) }.max() ?? 0, 0, "The refractive rim must still render.")
        XCTAssertEqual(alpha(106, 19), 0, "System material in the center would blur or tint the desktop.")
        XCTAssertEqual(backdrop.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertNil(glass.tintColor)
        XCTAssertNil(content.shadow, "Clear glass must not composite a second shadow over the icon artwork.")

        appearance.frostAmount = ShelfAppearance.defaultFrostAmount
        backdrop.apply(appearance)
        let mild = alpha(106, 19)
        XCTAssertGreaterThan(mild, 0, "The default scatters some background light in the interior.")
        XCTAssertLessThan(mild, alpha(106, 2), "The curved edge samples more native glass than the flat center.")
        XCTAssertNil(glass.tintColor)
        XCTAssertEqual(backdrop.layer?.backgroundColor?.alpha ?? 0, 0)
        appearance.frostAmount = 1
        backdrop.apply(appearance)
        XCTAssertGreaterThan(alpha(106, 19), mild)
        appearance.frostAmount = 0
        backdrop.apply(appearance)
        XCTAssertEqual(alpha(106, 19), 0)

        appearance.intensity = 0.8
        backdrop.apply(appearance)
        let tint = try XCTUnwrap(backdrop.layer?.backgroundColor)
        XCTAssertGreaterThan(tint.alpha, 0)
        XCTAssertGreaterThan(try XCTUnwrap(NSColor(cgColor: tint)?.usingColorSpace(.sRGB)).redComponent, 0.98)
        appearance.intensity = 0
        backdrop.apply(appearance)
        XCTAssertEqual(backdrop.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertNil(glass.tintColor)
    }
}

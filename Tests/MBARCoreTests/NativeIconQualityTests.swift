import XCTest
import AppKit
@testable import MBARCore

final class NativeIconQualityTests: XCTestCase {
    func image(_ color: NSColor, rect: NSRect = NSRect(x: 8, y: 10, width: 20, height: 18)) -> CGImage {
        let image = NSImage(size: NSSize(width: 44, height: 40), flipped: false) { _ in
            color.setFill(); rect.fill(); return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
    func testWhiteTransparentNativeGlyphIsVisibleAndBecomesTemplate() throws {
        let prepared = try XCTUnwrap(NativeIconQuality.prepare(image(.white)))
        XCTAssertEqual(prepared.mode, .template)
        XCTAssertLessThan(prepared.image.width, 44)
        XCTAssertLessThan(prepared.image.height, 40)
    }
    func testColorNativeGlyphPreservesItsColor() throws {
        XCTAssertEqual(try XCTUnwrap(NativeIconQuality.prepare(image(.systemYellow))).mode, .original)
    }
    func testBlankClippedOpaqueAndFadedFramesAreRejected() {
        XCTAssertNil(NativeIconQuality.prepare(image(.clear)))
        XCTAssertNil(NativeIconQuality.prepare(image(.white, rect: NSRect(x: 0, y: 0, width: 44, height: 40))))
        XCTAssertNil(NativeIconQuality.prepare(image(.white, rect: NSRect(x: 0, y: 10, width: 20, height: 18))))
        XCTAssertNil(NativeIconQuality.prepare(image(NSColor.white.withAlphaComponent(0.2))))
    }
}

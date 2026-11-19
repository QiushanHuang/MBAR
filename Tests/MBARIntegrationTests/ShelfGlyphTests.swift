import AppKit
import MBARCore
import SwiftUI
import XCTest
@testable import MBAR

final class ShelfGlyphTests: XCTestCase {
    @MainActor func testDarkAutomaticGlyphAndExplicitOriginalUseDifferentInkOnClearGlass() throws {
        _ = NSApplication.shared
        let source = image(.black)
        XCTAssertTrue(ShelfGlyph.usesSingleInk(source))
        let automatic = try rendered(source, preserveOriginal: false)
        XCTAssertGreaterThan(automatic(10, 10).redComponent, 0.9)
        let original = try rendered(source, preserveOriginal: true)
        XCTAssertLessThan(original(10, 10).redComponent, 0.1)
        // An explicit black silhouette gets a light edge on black, confined to
        // the outline; there is no colored button plate or opaque icon square.
        XCTAssertGreaterThan(original(3, 10).redComponent, 0.18)
        XCTAssertLessThan(original(1, 10).redComponent, 0.02)
    }

    @MainActor func testColoredOrTwoInkArtworkPreservesItsInternalDetail() throws {
        _ = NSApplication.shared
        for badge in [NSColor.red, NSColor.white] {
            let art = image(.black, badge: badge)
            let cg = try XCTUnwrap(art.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertFalse(ShelfGlyph.usesSingleInk(art))
            XCTAssertEqual(try XCTUnwrap(NativeIconQuality.prepare(cg)).mode, .original)
            let pixel = try rendered(art, preserveOriginal: false)
            XCTAssertLessThan(pixel(6, 10).redComponent, 0.1)
            XCTAssertGreaterThan(pixel(13, 10).redComponent, 0.9)
            let reference = try rendered(art, preserveOriginal: true, clear: false)(13, 10)
            let actual = pixel(13, 10)
            XCTAssertEqual(actual.redComponent, reference.redComponent, accuracy: 1 / 255)
            XCTAssertEqual(actual.greenComponent, reference.greenComponent, accuracy: 1 / 255)
            XCTAssertEqual(actual.blueComponent, reference.blueComponent, accuracy: 1 / 255)
        }
    }

    private func image(_ ink: NSColor, badge: NSColor? = nil) -> NSImage {
        NSImage(size: CGSize(width: 20, height: 20), flipped: false) { _ in
            ink.setFill()
            CGRect(x: 4, y: 4, width: 12, height: 12).fill()
            if let badge {
                badge.setFill()
                CGRect(x: 10, y: 6, width: 5, height: 8).fill()
            }
            return true
        }
    }

    @MainActor private func rendered(_ source: NSImage, preserveOriginal: Bool, clear: Bool = true) throws -> (Int, Int) -> NSColor {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { throw XCTSkip("Requires transparent desktop material.") }
        let glyph = ShelfGlyph(image: source, onClearGlass: clear, preservesOriginalInk: preserveOriginal)
            .frame(width: 20, height: 20)
            .background(.black)
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        return { x, y in bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)! }
    }
}

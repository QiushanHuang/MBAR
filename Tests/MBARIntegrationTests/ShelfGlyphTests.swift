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
        let automatic = try rendered(source, preserveOriginal: false, treatment: .darkPlate)
        XCTAssertGreaterThan(automatic(10, 10).redComponent, 0.9)
        let original = try rendered(source, preserveOriginal: true, treatment: .darkPlate)
        XCTAssertLessThan(original(10, 10).redComponent, 0.1)
        // The original stays black. A pale backing shows through its transparent
        // regions, but stops before the surrounding shelf.
        XCTAssertGreaterThan(original(1, 10).redComponent, 0.8)
        XCTAssertLessThan(original(-4, 10).redComponent, 0.02)
        let light = try rendered(source, preserveOriginal: false, treatment: .lightPlate)
        XCTAssertLessThan(light(10, 10).redComponent, 0.1)
        XCTAssertGreaterThan(light(1, 10).redComponent, 0.8)
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

    @MainActor private func rendered(_ source: NSImage, preserveOriginal: Bool, clear: Bool = true, treatment: ShelfIconTreatment = .automatic) throws -> (Int, Int) -> NSColor {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { throw XCTSkip("Requires transparent desktop material.") }
        let glyph = ShelfGlyph(image: source, onClearGlass: clear, treatment: treatment, preservesOriginalInk: preserveOriginal)
            .frame(width: 20, height: 20)
            .padding(4)
            .background(.black)
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        return { x, y in bitmap.colorAt(x: x + 4, y: y + 4)!.usingColorSpace(.sRGB)! }
    }
}

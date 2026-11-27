import AppKit
import MBARCore
import SwiftUI
import XCTest
@testable import MBAR

final class ShelfGlyphTests: XCTestCase {
    @MainActor func testInkModesOnlyPaintTheSourceShape() throws {
        _ = NSApplication.shared
        let source = image(.black)
        XCTAssertTrue(ShelfGlyph.usesSingleInk(source))
        let background = try rendered(source, preserveOriginal: true, clear: false)(-3, 0)
        for mode in ShelfIconTreatment.allCases {
            let bitmap = try rendered(source, preserveOriginal: false, treatment: mode)
            // Sample in the image canvas as well as its margin: there must be
            // no cell fill in automatic, dark ink or light ink modes.
            for x in [-3, 0, 19, 22] {
                XCTAssertEqual(bitmap(x, 0).greenComponent, background.greenComponent, accuracy: 1 / 255)
            }
            if mode == .darkInk { XCTAssertLessThan(bitmap(10, 10).redComponent, 0.1) }
            if mode == .lightInk { XCTAssertGreaterThan(bitmap(10, 10).redComponent, 0.9) }
            let original = try rendered(source, preserveOriginal: true, treatment: mode)
            XCTAssertLessThan(original(10, 10).redComponent, 0.1)
            XCTAssertEqual(original(0, 0).greenComponent, background.greenComponent, accuracy: 1 / 255)
        }
    }

    @MainActor func testSystemInkReversesWithAppearanceAndFixedInkKeepsItsPolarity() throws {
        let source = image(.black)
        source.isTemplate = true
        for scheme: ColorScheme in [.light, .dark] {
            for mode: ShelfIconTreatment in [.system, .lightInk, .darkInk] {
                let value = try rendered(source, preserveOriginal: false, treatment: mode, scheme: scheme)(10, 10)
                let white = mode == .lightInk || (mode == .system && scheme == .dark)
                XCTAssertEqual(value.redComponent, white ? 1 : 0, accuracy: 0.04)
            }
        }
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

    @MainActor private func rendered(_ source: NSImage, preserveOriginal: Bool, clear: Bool = true, treatment: ShelfIconTreatment = .automatic, scheme: ColorScheme = .light) throws -> (Int, Int) -> NSColor {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { throw XCTSkip("Requires transparent desktop material.") }
        let glyph = ShelfGlyph(image: source, onClearGlass: clear, treatment: treatment, preservesOriginalInk: preserveOriginal)
            .frame(width: 20, height: 20)
            .padding(4)
            .background(Color(.sRGB, red: 0.3, green: 0.6, blue: 0.7))
        let renderer = ImageRenderer(content: glyph.environment(\.colorScheme, scheme))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        return { x, y in bitmap.colorAt(x: x + 4, y: y + 4)!.usingColorSpace(.sRGB)! }
    }
}

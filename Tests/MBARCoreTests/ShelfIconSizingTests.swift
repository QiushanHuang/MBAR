import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MBARCore

final class ShelfIconSizingTests: XCTestCase {
    func testNativePointsDoNotExpandToFillHitAreaAndAspectSurvivesLimits() {
        let arrow = CGSize(width: 14, height: 9)
        XCTAssertEqual(ShelfMetrics.glyphSize(arrow), arrow)
        XCTAssertEqual(ShelfMetrics.itemWidth(arrow), 24)
        XCTAssertEqual(ShelfMetrics.glyphSize(arrow, scale: 1.5), CGSize(width: 21, height: 13.5))
        XCTAssertEqual(ShelfMetrics.glyphSize(CGSize(width: 200, height: 20), scale: 1.5),
                       CGSize(width: 300, height: 30))
        let veryWide = ShelfMetrics.glyphSize(CGSize(width: 500, height: 20), scale: 1.5)
        XCTAssertEqual(veryWide.width, 316)
        XCTAssertEqual(veryWide.width / veryWide.height, 25, accuracy: 0.00001)
        XCTAssertEqual(ShelfMetrics.glyphSize(nil), CGSize(width: 18, height: 18))
    }

    func testTallNativeGlyphRetainsPointHeightAndExpandsThePanel() {
        let measured = CGSize(width: 20, height: 29)
        for scale in [1.0, 1.5] {
            let glyph = ShelfMetrics.glyphSize(measured, scale: scale)
            XCTAssertEqual(glyph.height, measured.height * scale)
            XCTAssertEqual(glyph.width / glyph.height, measured.width / measured.height, accuracy: 0.0001)
            let strip = ShelfMetrics.size(style: .strip, itemWidths: [ShelfMetrics.itemWidth(measured, scale: scale)],
                                         available: CGSize(width: 1000, height: 700), showsLock: true,
                                         scale: scale, tallestGlyphHeight: glyph.height)
            XCTAssertGreaterThanOrEqual(strip.height, glyph.height + 12)
            XCTAssertGreaterThanOrEqual(ShelfMetrics.tileHeight(scale: scale, tallestGlyphHeight: glyph.height), glyph.height + 32)
            XCTAssertGreaterThanOrEqual(ShelfMetrics.listRowHeight(scale: scale, tallestGlyphHeight: glyph.height), glyph.height + 12)
        }
    }

    func testScaleIncreasesRowClearanceWithoutShrinkingTheDefaultPanel() {
        for scale in [0.7, 1, 1.5] {
            let glyph = ShelfMetrics.glyphSize(CGSize(width: 24, height: 24), scale: scale)
            let strip = ShelfMetrics.size(style: .strip, itemWidths: [ShelfMetrics.itemWidth(glyph)],
                                         available: CGSize(width: 1000, height: 700), showsLock: true, scale: scale)
            XCTAssertGreaterThanOrEqual(strip.height, glyph.height + 12)
            XCTAssertGreaterThanOrEqual(ShelfMetrics.tileHeight(scale: scale), glyph.height + 32)
            XCTAssertGreaterThanOrEqual(ShelfMetrics.listRowHeight(scale: scale), glyph.height + 12)
        }
    }

    func testOrientedRetinaResourceUsesRenderedAxes() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 128,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 2, y: 2, width: 20, height: 12))
        let data = NSMutableData()
        let dst = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dst, try XCTUnwrap(ctx.makeImage()), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        let decoded = try XCTUnwrap(IconImageDecoder.decode(data as Data, path: "tray@2x.tiff"))
        XCTAssertEqual(decoded.resourcePointSize, CGSize(width: 8, height: 16))
        let normalized = try XCTUnwrap(NSBitmapImageRep(data: decoded.png))
        XCTAssertEqual(normalized.pixelsWide, 16)
        XCTAssertEqual(normalized.pixelsHigh, 32)
    }

    func testRetinaNativeCaptureMeasuresTrimmedGlyphIncludingOnePixelBorder() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 80, height: 48, bitsPerComponent: 8, bytesPerRow: 320,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 8, y: 8, width: 50, height: 24))
        let capture = try XCTUnwrap(ctx.makeImage())
        let prepared = try XCTUnwrap(NativeIconQuality.prepare(capture, sourcePointSize: CGSize(width: 40, height: 24)))
        XCTAssertEqual(prepared.image.width, 52)
        XCTAssertEqual(prepared.image.height, 26)
        XCTAssertEqual(prepared.pointSize, CGSize(width: 26, height: 13))
        XCTAssertEqual(ShelfMetrics.glyphSize(prepared.pointSize), prepared.pointSize)
        XCTAssertNil(try XCTUnwrap(NativeIconQuality.prepare(capture)).pointSize)
        let scaledResource = try XCTUnwrap(IconImageDecoder.decode(prepared.image.png, path: "tray@2x.png"))
        XCTAssertEqual(scaledResource.resourcePointSize, prepared.pointSize)
        let genericResource = try XCTUnwrap(IconImageDecoder.decode(prepared.image.png, path: "user.png"))
        XCTAssertNil(genericResource.resourcePointSize)
    }
}

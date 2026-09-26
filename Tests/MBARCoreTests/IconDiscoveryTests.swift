import XCTest
import AppKit
@testable import MBARCore

final class IconDiscoveryTests: XCTestCase {
    func png() -> Data {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 24, height: 24)).fill(); return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
    func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tray"), withIntermediateDirectories: true)
        try png().write(to: root.appendingPathComponent("tray/statusItemTemplate.png"))
        return root
    }
    func testDiscoversActualImageAndRefusesIncompleteAutoAdoption() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let found = IconResourceDiscovery.scan(resources: root)
        XCTAssertTrue(found.complete)
        XCTAssertEqual(found.candidates.count, 1)
        XCTAssertNotNil(IconRanker.automaticIndex(found.candidates.map(\.evidence), complete: found.complete, itemCount: 1))
        let capped = IconResourceDiscovery.scan(resources: root, limits: .init(maxEntries: 1))
        XCTAssertFalse(capped.complete)
    }
    func testSymlinkEscapeAndMalformedImagesCannotBecomeCandidates() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("tray/otherTrayTemplate.png"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        try Data("not a png".utf8).write(to: root.appendingPathComponent("tray/brokenTrayTemplate.png"))
        let found = IconResourceDiscovery.scan(resources: root)
        XCTAssertFalse(found.complete)
        XCTAssertEqual(found.candidates.count, 1)
        XCTAssertNil(IconResourceDiscovery.read(.file("../escape.png"), resources: root, imports: root))
    }
    func testImportNormalizationPreservesTransparencyAndRejectsGarbage() throws {
        let decoded = try XCTUnwrap(IconImageDecoder.decode(png(), path: "test.png"))
        XCTAssertTrue(decoded.transparent)
        XCTAssertGreaterThan(decoded.png.count, 0)
        XCTAssertNil(IconImageDecoder.decode(Data("bad".utf8), path: "test.png"))
    }
    func testStrongNamedResourceGetsDecodeBudgetBeforeWeakIcons() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<20 { try png().write(to: root.appendingPathComponent("icon-\(i).png")) }
        let result = IconResourceDiscovery.scan(resources: root, limits: .init(maxCandidates: 1))
        XCTAssertEqual(result.candidates.first?.locator, .file("tray/statusItemTemplate.png"))
        XCTAssertFalse(result.complete) // Omitted candidates still prevent automatic adoption.
    }
    func testSmallImagesNamedAfterTheirAppBecomeManualCandidatesOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Example.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try png().write(to: resources.appendingPathComponent("exampleDark@2x.png"))
        let scan = IconResourceDiscovery.scan(resources: resources)
        XCTAssertEqual(scan.candidates.count, 1)
        XCTAssertNil(IconRanker.automaticIndex(scan.candidates.map(\.evidence), complete: scan.complete, itemCount: 1))
    }
    func testStrictScaleVariantsCollapseOnlyWhenRenderedArtworkMatches() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("tray/statusItemTemplate.png"))
        for size in [32, 64] {
            let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
                NSColor.black.setFill()
                NSRect(x: size / 4, y: size / 4, width: size / 2, height: size / 2).fill()
                return true
            }
            let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try data.write(to: root.appendingPathComponent(size == 32 ? "tray/trayTemplate.png" : "tray/trayTemplate@2x.png"))
        }
        let scan = IconResourceDiscovery.scan(resources: root)
        XCTAssertEqual(scan.candidates.count, 2)
        XCTAssertNotNil(IconRanker.automaticIndex(scan.candidates.map(\.evidence), complete: scan.complete, itemCount: 1))
    }
}

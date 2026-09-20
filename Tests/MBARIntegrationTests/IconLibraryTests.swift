import XCTest
import AppKit
import MBARCore
@testable import MBAR

final class IconLibraryTests: XCTestCase {
    func png(_ color: NSColor = .black) -> Data {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            color.setFill(); NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 24, height: 24)).fill(); return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
    func fixture(_ root: URL, version: String = "1", count: Int = 1) throws -> IconApplication {
        let resources = root.appendingPathComponent("Test.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("tray"), withIntermediateDirectories: true)
        let file = resources.appendingPathComponent("tray/trayTemplate.png")
        if !FileManager.default.fileExists(atPath: file.path) { try png().write(to: file) }
        return IconApplication(identity: IconAppIdentity(bundleID: "test.app", path: root.appendingPathComponent("Test.app").path, version: version, shortVersion: version), resources: resources, pid: 123, itemCount: count, item: nil)
    }
    @MainActor func settle(_ library: IconLibrary) async throws {
        for _ in 0..<300 {
            if !library.entry("test.app").scanning { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Icon library did not settle")
    }
    @MainActor func testAutomaticDiscoverySelectionRestartUpdateAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(root)
        let store = root.appendingPathComponent("store")
        let library = IconLibrary(directory: store)
        library.request(app); try await settle(library)
        XCTAssertEqual(library.entry(app.bundle).state, .automatic)
        let candidate = try XCTUnwrap(library.entry(app.bundle).candidates.first)
        XCTAssertNotNil(IconResourceDiscovery.safeURL(candidate.locator.resourcePath, under: app.resources), "root=\(app.resources.path) candidate=\(candidate.locator.label)")
        XCTAssertEqual(IconResourceDiscovery.read(candidate.locator, resources: app.resources, imports: library.imports).map(IconDigest.sha256), candidate.evidence.digest)
        try await library.choose(candidate, mode: .original, bundle: app.bundle)
        try await settle(library)
        XCTAssertEqual(library.entry(app.bundle).state, .userSelected)
        let restarted = IconLibrary(directory: store)
        restarted.request(try fixture(root, version: "2")); try await settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .userSelected)
        try png(.red).write(to: app.resources.appendingPathComponent("tray/trayTemplate.png"))
        restarted.request(try fixture(root, version: "3")); try await settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .stale)
        XCTAssertNil(restarted.entry(app.bundle).image)
        try restarted.reset(app.bundle); try await settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .automatic)
        try restarted.undo(app.bundle); try await settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .stale)
    }
    @MainActor func testCustomSelectionWinsOverLateScanAndSurvivesSourceRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(root)
        let library = IconLibrary(directory: root.appendingPathComponent("store"))
        library.request(app)
        let custom = try XCTUnwrap(IconImageDecoder.decode(png(.blue), path: "custom.png"))
        try library.saveImport(custom, mode: .original, bundle: app.bundle)
        try await settle(library)
        XCTAssertEqual(library.entry(app.bundle).state, .custom)
        try FileManager.default.removeItem(at: app.resources.appendingPathComponent("tray/trayTemplate.png"))
        library.request(app, force: true); try await settle(library)
        XCTAssertEqual(library.entry(app.bundle).state, .custom)
        XCTAssertNotNil(library.entry(app.bundle).image)
        library.remove(app.bundle)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(library.entries[app.bundle])
    }
    @MainActor func testMultipleItemsNeverUseSingleResourceOrCustomMapping() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(root, count: 2)
        let library = IconLibrary(directory: root.appendingPathComponent("store"))
        library.request(app)
        XCTAssertEqual(library.entry(app.bundle).state, .multiple)
        XCTAssertNil(library.entry(app.bundle).image)
        let decoded = try XCTUnwrap(IconImageDecoder.decode(png(), path: "custom.png"))
        XCTAssertThrowsError(try library.saveImport(decoded, mode: .template, bundle: app.bundle))
    }
    @MainActor func testExitDuringDiscoveryCannotPersistLateAutomaticChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(root), directory = root.appendingPathComponent("store")
        let library = IconLibrary(directory: directory)
        library.request(app)
        library.remove(app.bundle)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(library.entries[app.bundle])
        XCTAssertNil(try IconMappingStore(directory: directory).mapping(for: app.identity.key))
    }
}

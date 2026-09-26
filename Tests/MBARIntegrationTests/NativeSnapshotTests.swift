import XCTest
import AppKit
import MBARCore
@testable import MBAR

final class NativeSnapshotTests: XCTestCase {
    @MainActor func testLiveVisibleIconProbeWhenExplicitlyRequested() async throws {
        guard let requested = ProcessInfo.processInfo.environment["MBAR_NATIVE_PROBE_BUNDLES"] else {
            throw XCTSkip("Live native capture requires an explicitly selected application and existing permissions.")
        }
        let bundles = Set(requested.split(separator: ",").map(String.init))
        let snapshot = await withCheckedContinuation { continuation in
            MenuDiscovery().scan { continuation.resume(returning: $0) }
        }
        XCTAssertNil(snapshot.error)
        let selected = snapshot.items.filter { bundles.contains($0.bundle) }
        XCTAssertEqual(Set(selected.map(\.bundle)), bundles)
        for item in selected {
            let prepared = try await NativeIconCapture.capture(item)
            XCTAssertGreaterThan(prepared.image.png.count, 0)
            print("NATIVE_PROBE \(item.bundle) \(prepared.image.width)x\(prepared.image.height) \(prepared.mode.rawValue)")
        }
    }
    @MainActor func testNativeSnapshotPersistsAndBecomesStaleAfterAppUpdate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = IconLibraryTests(), app = try fixture.fixture(root), library = IconLibrary(directory: root.appendingPathComponent("store"))
        library.request(app); try await fixture.settle(library)
        let data = fixture.png(.white), cg = NSBitmapImageRep(data: data)!.cgImage!
        let prepared = try XCTUnwrap(NativeIconQuality.prepare(cg))
        let preview = NativeIconPreview(prepared: prepared, identity: app.identity, pid: app.pid, capturedAt: Date())
        try library.saveNative(preview, mode: .template, bundle: app.bundle)
        try await fixture.settle(library)
        XCTAssertEqual(library.entry(app.bundle).state, .nativeSnapshot)
        let restarted = IconLibrary(directory: root.appendingPathComponent("store"))
        restarted.request(app); try await fixture.settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .nativeSnapshot)
        restarted.request(try fixture.fixture(root, version: "2")); try await fixture.settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .stale)
        XCTAssertThrowsError(try restarted.saveNative(preview, mode: .template, bundle: app.bundle))
    }
}

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
            let points = try XCTUnwrap(prepared.pointSize)
            let image = try XCTUnwrap(IconLibrary.image(prepared.image.png, mode: prepared.mode, pointSize: points))
            let displayed = ShelfMetrics.glyphSize(image.size)
            XCTAssertEqual(image.size.width, points.width, accuracy: 0.1)
            XCTAssertEqual(image.size.height, points.height, accuracy: 0.1)
            print("NATIVE_PROBE \(item.bundle) pixels=\(prepared.image.width)x\(prepared.image.height) points=\(points) shelf@100%=\(displayed) \(prepared.mode.rawValue)")
        }
    }
    /// The named local fixture must alternate a tall glyph and a wide glyph at a fixed item position.
    @MainActor func testChangingNativeGlyphWhenFixtureIsRequested() async throws {
        guard let bundle = ProcessInfo.processInfo.environment["MBAR_CHANGING_GLYPH_FIXTURE"] else {
            throw XCTSkip("Set MBAR_CHANGING_GLYPH_FIXTURE to an already running test fixture.")
        }
        XCTAssertTrue(AXIsProcessTrusted() && CGPreflightScreenCaptureAccess())
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { return }
        let snapshot = await withCheckedContinuation { continuation in
            MenuDiscovery().scan { continuation.resume(returning: $0) }
        }
        let item = try XCTUnwrap(snapshot.items.first { $0.bundle == bundle })
        let frames = await MenuDiscovery().visibleFrames([item])
        print("CHANGING_GLYPH visible=\(String(describing: frames.first?.frame))")
        guard !frames.isEmpty else {
            XCTFail("The fixture has no visible, unambiguous menu-bar frame on this desktop.")
            return
        }
        var seen = Set<String>()
        var previousWide: Bool?
        var transitions = 0
        for _ in 0..<12 {
            let prepared = try await NativeIconCapture.capture(item)
            let image = prepared.image
            let digest = IconDigest.sha256(image.png)
            let wide = image.width > image.height
            if let previousWide, previousWide != wide { transitions += 1 }
            previousWide = wide
            seen.insert(digest)
            print("CHANGING_GLYPH \(image.width)x\(image.height) \(digest.prefix(12))")
            if seen.count >= 2 && transitions >= 2 { break }
            try await Task.sleep(nanoseconds: 350_000_000)
        }
        XCTAssertGreaterThanOrEqual(seen.count, 2)
        XCTAssertGreaterThanOrEqual(transitions, 2)
    }
    @MainActor func testLegacySnapshotWithoutDisplayScaleKeepsAspectAtMenuReferenceSize() throws {
        let app = IconAppIdentity(bundleID: "test", path: "/test", version: "1", shortVersion: "1")
        let old = IconMapping(identity: app, locator: .imported("snapshot.png"), digest: "fixture",
                              mode: .original, origin: .nativeSnapshot)
        let encoded = try JSONEncoder().encode(old)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(fields["pointSize"])
        let restored = try JSONDecoder().decode(IconMapping.self, from: encoded)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 20,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 320, bitsPerPixel: 32))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = try XCTUnwrap(IconLibrary.image(png, mode: restored.mode, pointSize: restored.pointSize))
        XCTAssertEqual(image.size, CGSize(width: 72, height: 18))
        let wrongBox = try XCTUnwrap(IconLibrary.image(png, mode: .original, pointSize: CGSize(width: 8, height: 18)))
        XCTAssertEqual(wrongBox.size, CGSize(width: 8, height: 2))
    }

    @MainActor func testNativeSnapshotPersistsAndBecomesStaleAfterAppUpdate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = IconLibraryTests(), app = try fixture.fixture(root), library = IconLibrary(directory: root.appendingPathComponent("store"))
        library.request(app); try await fixture.settle(library)
        let data = fixture.png(.white), cg = NSBitmapImageRep(data: data)!.cgImage!
        let capturedPoints = CGSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
        let prepared = try XCTUnwrap(NativeIconQuality.prepare(cg, sourcePointSize: capturedPoints))
        let preview = NativeIconPreview(prepared: prepared, identity: app.identity, pid: app.pid, capturedAt: Date())
        try library.saveNative(preview, mode: .template, bundle: app.bundle)
        try await fixture.settle(library)
        XCTAssertEqual(library.entry(app.bundle).state, .nativeSnapshot)
        let restarted = IconLibrary(directory: root.appendingPathComponent("store"))
        restarted.request(app); try await fixture.settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .nativeSnapshot)
        XCTAssertEqual(restarted.entry(app.bundle).mapping?.pointSize, prepared.pointSize)
        XCTAssertEqual(restarted.entry(app.bundle).image?.size, prepared.pointSize)
        restarted.request(try fixture.fixture(root, version: "2")); try await fixture.settle(restarted)
        XCTAssertEqual(restarted.entry(app.bundle).state, .stale)
        XCTAssertThrowsError(try restarted.saveNative(preview, mode: .template, bundle: app.bundle))
    }
}

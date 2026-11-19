import XCTest
import AppKit
import MBARCore
@testable import MBAR

final class ShelfSamplingTests: XCTestCase {
    @MainActor func testOneCaptureAcceptsOnlyItemsThatStayedInPlace() async throws {
        let frame = CGRect(x: 80, y: 0, width: 30, height: 30)
        let items = ["a", "b", "c"].map { name in
            MenuItem(id: name, bundle: name, name: name, title: name, pid: getpid(),
                     element: AXUIElementCreateApplication(getpid()), frame: frame)
        }
        var passes = 0
        var captured: [String] = []
        let result = try await NativeIconCapture.sample(items, frames: { current in
            passes += 1
            return current.map { item in
                var updated = item
                if (item.id == "b" && passes == 2) || (item.id == "c" && passes == 3) {
                    updated.frame = frame.offsetBy(dx: 10, dy: 0)
                }
                return updated
            }
        }, capture: { stable in
            captured = stable.map(\.id)
            let image = NSImage(data: IconLibraryTests().png())!
            return CapturedIcons(images: Dictionary(uniqueKeysWithValues: stable.map { ($0.id, image) }))
        })
        XCTAssertEqual(captured, ["a", "c"])
        XCTAssertEqual(Set(result.icons.keys), ["a"])
    }

    @MainActor func testCancellationDuringPositionCheckNeverCaptures() async {
        let item = MenuItem(id: "a", bundle: "a", name: "A", title: "A", pid: getpid(),
                            element: AXUIElementCreateApplication(getpid()), frame: .zero)
        let task = Task {
            try await NativeIconCapture.sample([item], frames: { items in
                withUnsafeCurrentTask { $0?.cancel() }
                return items
            }, capture: { _ in
                XCTFail("Cancelled sampling reached the screen capture API")
                return CapturedIcons(images: [:])
            })
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    /// Opt-in read-only probe of the entire polling session, including fallback on close.
    @MainActor func testOpenShelfPollsVisibleItemsAndReleasesFramesOnClose() async throws {
        guard let setting = ProcessInfo.processInfo.environment["MBAR_SHELF_PROBE_BUNDLES"] else {
            throw XCTSkip("Requires chosen visible items and existing screen recording and accessibility permissions.")
        }
        let bundles = Set(setting.split(separator: ",").map(String.init))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: folder.lastPathComponent))
        defer { defaults.removePersistentDomain(forName: folder.lastPathComponent); try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(iconLibrary: IconLibrary(directory: folder), defaults: defaults)
        let snapshot: MenuSnapshot = await withCheckedContinuation { continuation in
            model.discovery.scan { continuation.resume(returning: $0) }
        }
        model.items = snapshot.items.filter { bundles.contains($0.bundle) }
        XCTAssertEqual(Set(model.items.map(\.bundle)), bundles)
        model.policy = ShelfPolicy(assignments: Dictionary(uniqueKeysWithValues: bundles.map { ($0, .automatic) }))
        model.iconLibrary.reconcile(model.items, priority: bundles)
        model.shelfLiveIcons = true
        model.shelfVisible = { true }
        let service = ShelfLiveIcons()
        service.start(model: model, display: CGDisplayBounds(CGMainDisplayID()))
        defer { service.stop(model: model); model.iconLibrary.shutdown() }
        var unique: [String: Set<String>] = [:]
        var previous: [String: NSImage] = [:]
        var counts: [String: Int] = [:]
        let deadline = ContinuousClock.now + .seconds(16)
        while ContinuousClock.now < deadline {
            for item in model.items {
                guard let sample = model.liveImages[item.id], sample.image !== previous[item.id],
                      let data = sample.image.tiffRepresentation else { continue }
                previous[item.id] = sample.image
                unique[item.id, default: []].insert(IconDigest.sha256(data))
                counts[item.id, default: 0] += 1
            }
            if counts.count == bundles.count && counts.values.allSatisfy({ $0 >= 3 }) { break }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTAssertEqual(counts.count, bundles.count)
        for item in model.items {
            XCTAssertGreaterThanOrEqual(counts[item.id, default: 0], 2)
            print("SHELF_PROBE \(item.bundle) accepted=\(counts[item.id, default: 0]) distinct=\(unique[item.id]?.count ?? 0)")
        }
        model.shelfVisible = { false }
        service.stop(model: model)
        XCTAssertTrue(model.liveImages.isEmpty)
    }
}

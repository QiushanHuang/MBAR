import XCTest
@testable import MBAR

final class ShelfPreferencesTests: XCTestCase {
    @MainActor func testAppearanceChangesPersistAcrossLaunchesAndNotifyOpenShelf() throws {
        let suite = "MBARShelfPreferences-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(["example.app"], forKey: "selectedBundles")
        defaults.set(false, forKey: "showShelfLockButton")
        let model = AppModel(iconLibrary: IconLibrary(directory: directory), defaults: defaults)
        XCTAssertEqual(model.shelfStyle, .strip)
        XCTAssertEqual(model.shelfPlacement, .anchor)
        XCTAssertEqual(model.shelfAlignment, .left)
        XCTAssertFalse(model.shelfLiveIcons)
        XCTAssertFalse(model.shelfLock.showsButton)
        XCTAssertEqual(model.policy.category("example.app"), .automatic)

        var layouts = 0
        var liveChanges = 0
        model.onShelfContentChanged = { layouts += 1 }
        model.onShelfLiveIconsChanged = { liveChanges += 1 }
        model.shelfStyle = .grid
        model.shelfAlignment = .center
        model.shelfAlignment = .center
        model.shelfPlacement = .right
        model.shelfLiveIcons = true
        model.shelfLiveIcons = true
        XCTAssertEqual(layouts, 3)
        XCTAssertEqual(liveChanges, 1)

        let restored = AppModel(iconLibrary: IconLibrary(directory: directory), defaults: defaults)
        XCTAssertEqual(restored.shelfStyle, .grid)
        XCTAssertEqual(restored.shelfPlacement, .right)
        restored.shelfPlacement = .anchor
        XCTAssertEqual(restored.shelfAlignment, .center)
        XCTAssertTrue(restored.shelfLiveIcons)
        XCTAssertEqual(restored.policy.category("example.app"), .automatic)
        defaults.set("unknown", forKey: "shelfStyle")
        defaults.set("unknown", forKey: "shelfPlacement")
        defaults.set("unknown", forKey: "shelfAlignment")
        let fallback = AppModel(iconLibrary: IconLibrary(directory: directory), defaults: defaults)
        XCTAssertEqual(fallback.shelfStyle, .strip)
        XCTAssertEqual(fallback.shelfPlacement, .anchor)
        XCTAssertEqual(fallback.shelfAlignment, .left)
    }
}

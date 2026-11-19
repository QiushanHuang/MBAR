import XCTest
import MBARCore
@testable import MBAR

final class ShelfAppearanceTests: XCTestCase {
    @MainActor func testWorkingVariationPersistsWithoutOverwritingPreset() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        func launch() -> AppModel {
            AppModel(iconLibrary: IconLibrary(directory: directory), defaults: defaults)
        }

        let model = launch()
        let original = model.shelfAppearance
        let builtIn = model.selectedShelfPresetID
        var updates = 0
        model.onShelfAppearanceChanged = { updates += 1 }
        let edition = ShelfAppearance(material: .liquid, tint: ShelfTint(red: 0.3, green: 0.1, blue: 0.7), intensity: 0.65)
        model.setShelfAppearance(edition)
        model.saveShelfPreset(named: "  晚霞  ")
        let custom = model.selectedShelfPresetID
        XCTAssertNotEqual(custom, builtIn)
        XCTAssertEqual(model.shelfPresets.last?.name, "晚霞")
        XCTAssertEqual(updates, 1)
        var variation = edition
        variation.material = .translucent
        variation.intensity = 0.84
        variation.opacity = 0.50
        model.setShelfAppearance(variation)
        let reopened = launch()
        XCTAssertEqual(reopened.selectedShelfPresetID, custom)
        XCTAssertEqual(reopened.shelfAppearance, variation)
        XCTAssertEqual(reopened.shelfPresets.last?.appearance, edition)
        reopened.selectShelfPreset(custom)
        XCTAssertEqual(reopened.shelfAppearance, edition)
        reopened.setShelfAppearance(variation)
        reopened.updateShelfPreset(custom)
        reopened.selectShelfPreset(builtIn)
        XCTAssertEqual(reopened.shelfAppearance, original)
        reopened.selectShelfPreset(custom)
        XCTAssertEqual(reopened.shelfAppearance, variation)
        reopened.deleteShelfPreset(custom)
        XCTAssertEqual(reopened.selectedShelfPresetID, builtIn)
        XCTAssertEqual(launch().shelfAppearance, original)
        XCTAssertFalse(launch().shelfPresets.contains { $0.id == custom })
    }

    func testPreviouslySavedGlassKeepsRegularMaterialWhenClearGlassIsAdded() throws {
        let previous = Data("""
            {"selectedID":"clear","appearance":{"material":"liquid","tint":{"red":0.8,"green":0.92,"blue":1},"intensity":0},"customPresets":[]}
            """.utf8)
        var state = try JSONDecoder().decode(ShelfAppearancePreferences.self, from: previous)
        XCTAssertEqual(state.selectedID, "clear")
        XCTAssertEqual(state.appearance.material, .liquid)
        XCTAssertEqual(state.presets.first { $0.id == "clear" }?.appearance, state.appearance)
        state.select("apple-glass")
        XCTAssertEqual(state.appearance.material, .appleGlass)
        XCTAssertEqual(state.appearance.intensity, 0)
        XCTAssertEqual(try JSONDecoder().decode(ShelfAppearancePreferences.self, from: JSONEncoder().encode(state)), state)
    }

    func testInvalidNamesAndValuesAndBuiltInProtection() throws {
        var state = ShelfAppearancePreferences()
        let builtIns = state.presets
        var appearance = state.appearance
        appearance.intensity = .infinity
        state.customize(appearance)
        XCTAssertEqual(state.appearance.intensity, 0)
        XCTAssertFalse(state.save(named: " "))
        XCTAssertFalse(state.save(named: builtIns[0].name))
        XCTAssertTrue(state.save(named: "Blue"))
        XCTAssertFalse(state.save(named: " blue "))
        for preset in builtIns {
            state.update(preset.id)
            state.delete(preset.id)
        }
        XCTAssertEqual(state.presets.filter { !$0.isCustom }, builtIns)
        XCTAssertEqual(try JSONDecoder().decode(ShelfAppearancePreferences.self, from: JSONEncoder().encode(state)), state)
    }
}

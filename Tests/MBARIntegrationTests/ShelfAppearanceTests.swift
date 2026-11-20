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
        variation.frostAmount = 0.72
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
        appearance.frostAmount = 1.3
        state.customize(appearance)
        XCTAssertEqual(state.appearance.intensity, 0)
        XCTAssertEqual(state.appearance.frostAmount, 1)
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

    func testGlassIconTreatmentTravelsWithPresetAndLegacyCopiesUseAutomatic() throws {
        let legacyAppearance = """
            {"material":"appleGlass","tint":{"red":0.2,"green":0.3,"blue":0.6},"intensity":0.45,"frostAmount":0.15}
            """
        let data = Data("""
            {"selectedID":"custom.old","appearance":\(legacyAppearance),"customPresets":[
              {"id":"custom.old","name":"山色","appearance":\(legacyAppearance)}]}
            """.utf8)
        var preferences = try JSONDecoder().decode(ShelfAppearancePreferences.self, from: data)
        XCTAssertEqual(preferences.appearance.iconTreatment, .automatic)
        XCTAssertEqual(preferences.customPresets[0].appearance, preferences.appearance)
        var variation = preferences.appearance
        variation.iconTreatment = .darkPlate
        preferences.customize(variation)
        XCTAssertTrue(preferences.save(named: "入夜"))
        let copy = preferences.selectedID
        variation.iconTreatment = .lightPlate
        preferences.customize(variation)
        preferences = try JSONDecoder().decode(ShelfAppearancePreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(preferences.appearance, variation)
        preferences.select(copy)
        XCTAssertEqual(preferences.appearance.iconTreatment, .darkPlate)
        preferences.select("custom.old")
        XCTAssertEqual(preferences.appearance.iconTreatment, .automatic)
        XCTAssertEqual(preferences.appearance.intensity, 0.45)
    }

    func testFactoryFrostMigrationPreservesCustomGlassAndExplicitZero() throws {
        let oldJSON = """
            {"material":"appleGlass","tint":{"red":0.76,"green":0.91,"blue":1},"intensity":0,"opacity":0.74}
            """
        func restored(id: String, appearance: String) throws -> ShelfAppearancePreferences {
            let json = """
                {"selectedID":"\(id)","appearance":\(appearance),"customPresets":[
                  {"id":"custom.saved","name":"我的水晶","appearance":\(oldJSON)}]}
                """
            return try JSONDecoder().decode(ShelfAppearancePreferences.self, from: Data(json.utf8))
        }
        var state = try restored(id: "apple-glass", appearance: oldJSON)
        XCTAssertEqual(state.appearance.frostAmount, 0.35)
        XCTAssertEqual(state.appearance.intensity, 0)
        XCTAssertEqual(state.customPresets.first?.appearance.frostAmount, 0)
        state.select("custom.saved")
        XCTAssertEqual(state.appearance.frostAmount, 0)
        state.select("apple-glass")
        var clear = state.appearance
        clear.frostAmount = 0
        state.customize(clear)
        XCTAssertEqual(try JSONDecoder().decode(ShelfAppearancePreferences.self, from: JSONEncoder().encode(state)), state)

        let modifiedJSON = oldJSON.replacingOccurrences(of: "\"intensity\":0", with: "\"intensity\":0.42")
        let oldVariation = try restored(id: "apple-glass", appearance: modifiedJSON)
        XCTAssertEqual(oldVariation.appearance.intensity, 0.42)
        XCTAssertEqual(oldVariation.appearance.frostAmount, 0)
    }
}

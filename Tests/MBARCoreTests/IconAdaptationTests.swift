import XCTest
@testable import MBARCore

final class IconAdaptationTests: XCTestCase {
    func evidence(_ path: String, hash: String = "a") -> IconEvidence {
        IconEvidence(path: path, digest: hash, transparent: true, menuSized: true)
    }
    func testOnlyUniqueStrongCandidateCanBeAutomatic() {
        let strong = evidence("tray/statusItemTemplate@2x.png")
        XCTAssertEqual(IconRanker.automaticIndex([strong], complete: true, itemCount: 1), 0)
        XCTAssertNil(IconRanker.automaticIndex([evidence("icon.png")], complete: true, itemCount: 1))
        XCTAssertNil(IconRanker.automaticIndex([strong], complete: false, itemCount: 1))
        XCTAssertNil(IconRanker.automaticIndex([strong], complete: true, itemCount: 2))
    }
    func testCompoundLowercaseMenuNamesAreDiscoveredWithoutMatchingUnrelatedWords() {
        for name in ["statusicon.tiff", "menubarpinyin.pdf", "trayicon.png", "Status_Bar_Icon", "StatusBarIcon", "statusbar_ime_cn_icon"] {
            XCTAssertTrue(evidence(name).strongName, name)
            XCTAssertTrue(evidence(name).worthInspecting, name)
        }
        for name in ["portray.png", "statusquo.png", "toolbaricon.png"] { XCTAssertFalse(evidence(name).strongName, name) }
    }
    func testAmbiguousStateAndThemeVariantsNeedSelection() {
        let paths = ["tray/trayTemplate.png", "tray/otherTrayTemplate.png"]
        XCTAssertNil(IconRanker.automaticIndex(paths.enumerated().map { evidence($0.element, hash: String($0.offset)) }, complete: true, itemCount: 1))
        for path in ["tray/trayConnectedTemplate.png", "tray/tray-0Template.png", "tray/trayDarkTemplate.png", "tray/AppIconTemplate.png"] {
            XCTAssertNil(IconRanker.automaticIndex([evidence(path)], complete: true, itemCount: 1), path)
        }
        XCTAssertFalse(evidence("portrayTemplate.png").strongName)
    }
    func testByteDuplicatesDoNotCreateAmbiguity() {
        let entries = [evidence("tray/trayTemplate.png"), evidence("tray/copyTrayTemplate.png")]
        XCTAssertNotNil(IconRanker.automaticIndex(entries, complete: true, itemCount: 1))
    }
    func testOversizedArtworkAndThemeDirectoriesAreNotAutomatic() {
        let oversized = IconEvidence(path: "tray/trayTemplate.png", digest: "a", transparent: true, menuSized: false)
        XCTAssertNil(IconRanker.automaticIndex([oversized], complete: true, itemCount: 1))
        XCTAssertNil(IconRanker.automaticIndex([evidence("dark/trayTemplate.png")], complete: true, itemCount: 1))
    }
    func testMappingPersistsUndoAndProtectsCorruptStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try IconMappingStore(directory: root)
        let identity = IconAppIdentity(bundleID: "test.app", path: "/Applications/Test.app", version: "1", shortVersion: "1")
        let record = IconMapping(identity: identity, locator: .file("tray.png"), digest: "abc", mode: .template, origin: .userSelected)
        try store.set(record, for: identity.key)
        XCTAssertEqual(try IconMappingStore(directory: root).mapping(for: identity.key), record)
        try store.set(nil, for: identity.key)
        XCTAssertNil(store.mapping(for: identity.key))
        try store.undo(for: identity.key)
        XCTAssertEqual(store.mapping(for: identity.key), record)
        XCTAssertEqual(record.validation(current: IconAppIdentity(bundleID: "test.app", path: identity.path, version: "2", shortVersion: "2"), digest: "abc"), .valid)
        XCTAssertEqual(record.validation(current: identity, digest: "changed"), .needsConfirmation)
        XCTAssertEqual(record.validation(current: IconAppIdentity(bundleID: "test.app", path: "/Other/Test.app", version: "1", shortVersion: "1"), digest: "abc"), .differentInstallation)
        let url = root.appendingPathComponent("IconMappings.json")
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try IconMappingStore(directory: root))
        XCTAssertEqual(try String(contentsOf: url), "broken")
    }
    func testGenerationRejectsLateResultAfterSelectionAndExit() {
        var gate = IconRequestGate()
        let first = gate.begin("app")
        let second = gate.begin("app")
        XCTAssertFalse(gate.accepts("app", token: first))
        XCTAssertTrue(gate.accepts("app", token: second))
        gate.invalidate("app")
        XCTAssertFalse(gate.accepts("app", token: second))
    }
}

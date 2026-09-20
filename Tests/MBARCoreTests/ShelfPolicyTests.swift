import XCTest
import CoreGraphics
@testable import MBARCore
final class ShelfPolicyTests: XCTestCase {
    func testEntryClickBelongsToToggleNotOutsideDismissal() {
        let anchor = CGRect(x: -900, y: 960, width: 28, height: 22)
        XCTAssertTrue(ShelfDismissal.isEntryClick(CGPoint(x: -886, y: 970), anchor: anchor))
        XCTAssertFalse(ShelfDismissal.isEntryClick(CGPoint(x: -820, y: 970), anchor: anchor))
        XCTAssertFalse(ShelfDismissal.isEntryClick(CGPoint(x: -886, y: 950), anchor: anchor))
        XCTAssertFalse(ShelfDismissal.isEntryClick(CGPoint(x: -886, y: 970), anchor: nil))
    }
    func testLegacyChoicesMigrateToAutomaticWithoutOverwritingExplicitCategories() {
        let policy = ShelfPolicy(assignments: ["a": .always, "c": .visible], legacySelected: ["a", "b", "c"])
        XCTAssertEqual(policy.category("a"), .always)
        XCTAssertEqual(policy.category("b"), .automatic)
        XCTAssertEqual(policy.category("c"), .visible)
        XCTAssertEqual(policy.automatic, ["b"])
    }
    func testAlwaysHiddenNeverEntersOrdinaryShelfOrCaptureReveal() {
        let policy = ShelfPolicy(assignments: ["a": .automatic, "b": .always, "c": .visible])
        XCTAssertEqual(policy.automatic, ["a"])
        XCTAssertEqual(policy.hidden, ["a", "b"])
        // Loading icons must never temporarily reveal the automatic section.
        XCTAssertEqual(policy.hiddenWhileCapturing(), ["a", "b"])
        XCTAssertEqual(policy.hiddenWhileOpening("a"), ["b"])
        XCTAssertEqual(policy.hiddenWhileOpening("b"), ["a"])
    }
    func testShowAllOrNewSessionRejectsLateCaptureAndRehide() {
        var session = SnapshotSession()
        let old = session.begin()
        XCTAssertTrue(session.accepts(old))
        session.cancel()
        XCTAssertFalse(session.accepts(old))
        let next = session.begin()
        XCTAssertFalse(session.accepts(old))
        XCTAssertTrue(session.accepts(next))
    }
    func testOneRowKeepsWideStatusReadoutsAndPinsSpaceForSettings() {
        XCTAssertEqual(ShelfMetrics.height, 36)
        XCTAssertGreaterThan(ShelfMetrics.itemWidth(CGSize(width: 120, height: 30)), 80)
        XCTAssertEqual(ShelfMetrics.width(itemWidths: Array(repeating: 40, count: 30), available: 400), 400)
        XCTAssertGreaterThanOrEqual(ShelfMetrics.width(itemWidths: [], available: 400), 36)
    }
    func testCropUsesDisplayRelativeRetinaCoordinatesAndRejectsOffscreen() {
        let display = CGRect(x: -1512, y: 458, width: 1512, height: 982)
        let item = CGRect(x: -1400, y: 458, width: 40, height: 33)
        XCTAssertEqual(SnapshotCrop.rect(item: item, display: display, scale: 2), CGRect(x: 224, y: 0, width: 80, height: 66))
        XCTAssertNil(SnapshotCrop.rect(item: item.offsetBy(dx: -300, dy: 0), display: display, scale: 2))
        XCTAssertNil(SnapshotCrop.rect(item: item.offsetBy(dx: 0, dy: 200), display: display, scale: 2))
    }
}

import XCTest
@testable import MBARCore

final class ShelfLockTests: XCTestCase {
    func testLockKeepsShelfDuringOrdinaryInteractions() {
        var state = ShelfLockPolicy(showsButton: true)
        state.toggle()
        for reason in [ShelfCloseReason.outside, .escape, .toggle, .item, .settings, .applicationsChanged] {
            XCTAssertFalse(state.shouldClose(for: reason))
        }
        XCTAssertTrue(state.shouldClose(for: .recovery))
        state.toggle()
        XCTAssertTrue(state.shouldClose(for: .outside))
    }
    func testHidingControlUnlocksAndCannotCreateInvisibleLock() {
        var state = ShelfLockPolicy(showsButton: true)
        state.toggle(); state.setShowsButton(false)
        XCTAssertFalse(state.isLocked)
        state.toggle()
        XCTAssertFalse(state.isLocked)
        state.setShowsButton(true)
        XCTAssertFalse(state.isLocked)
    }
    func testLockControlHasReservedWidthEvenWhenIconsOverflow() {
        XCTAssertEqual(ShelfMetrics.width(itemWidths: [24, 24], available: 500, showsLock: true)
                       - ShelfMetrics.width(itemWidths: [24, 24], available: 500, showsLock: false), 30)
        XCTAssertEqual(ShelfMetrics.width(itemWidths: Array(repeating: 40, count: 30), available: 400, showsLock: true), 400)
    }
}

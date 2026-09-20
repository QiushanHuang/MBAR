import XCTest
@testable import MBARCore
final class MenuLifetimeTests: XCTestCase {
    func testClosingSubmenuDoesNotHideWhileMainMenuIsStillOpen() {
        var session = MenuLifetime()
        session.opened(); session.opened()
        XCTAssertFalse(session.closed())
        XCTAssertEqual(session.depth, 1)
        XCTAssertTrue(session.closed())
        XCTAssertEqual(session.depth, 0)
    }
    func testUnmatchedOrDuplicateCloseNeverTriggersRehide() {
        var session = MenuLifetime()
        XCTAssertFalse(session.closed())
        session.opened()
        XCTAssertTrue(session.closed())
        XCTAssertFalse(session.closed())
    }
}

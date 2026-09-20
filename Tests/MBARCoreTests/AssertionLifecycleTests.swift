import XCTest
@testable import MBARCore
final class AssertionLifecycleTests: XCTestCase {
    func testReplacementKeepsPreviousProtectionUntilNewAssertionSucceeds() {
        var state = AssertionLifecycle()
        XCTAssertEqual(state.begin(1), [])
        XCTAssertEqual(state.complete(1, success: true), [])
        XCTAssertEqual(state.active, 1)
        XCTAssertEqual(state.begin(2), [])
        XCTAssertEqual(state.active, 1)
        XCTAssertEqual(state.complete(2, success: true), [1])
        XCTAssertEqual(state.active, 2)
    }
    func testFailureKeepsOldAssertionAndRestoreReleasesPendingToo() {
        var state = AssertionLifecycle()
        _ = state.begin(1); _ = state.complete(1, success: true)
        _ = state.begin(2)
        XCTAssertEqual(state.complete(2, success: false), [2])
        XCTAssertEqual(state.active, 1)
        _ = state.begin(3)
        XCTAssertEqual(Set(state.restore()), [1, 3])
        XCTAssertNil(state.active)
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.complete(3, success: true), [3])
        XCTAssertNil(state.active)
    }
    func testDuplicateCompletionCannotInvalidateTheActiveAssertion() {
        var state = AssertionLifecycle()
        _ = state.begin(1); _ = state.complete(1, success: true)
        XCTAssertEqual(state.complete(1, success: true), [])
        XCTAssertEqual(state.active, 1)
    }

}

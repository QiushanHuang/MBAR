import XCTest
@testable import MBARCore

final class SystemTransitionTests: XCTestCase {
    func testSleepAndScreenNotificationsCannotResumeUntilWake() {
        var transition = MenuBarSystemTransition()
        let sleep = transition.begin(sleeping: true)
        XCTAssertFalse(transition.canResume(sleep))
        let screen = transition.begin()
        XCTAssertFalse(transition.canResume(screen))
        let wake = transition.begin(sleeping: false)
        XCTAssertTrue(transition.canResume(wake))
        XCTAssertFalse(transition.canResume(sleep))
        XCTAssertFalse(transition.canResume(screen))
    }
    func testOnlyLatestDisplayChangeMayResumeAfterAsyncScan() {
        var transition = MenuBarSystemTransition()
        let wake = transition.begin(sleeping: false)
        let display = transition.begin()
        XCTAssertFalse(transition.canResume(wake))
        XCTAssertTrue(transition.canResume(display))
        _ = transition.begin(sleeping: true)
        XCTAssertFalse(transition.canResume(display))
    }
}

import XCTest
import CoreGraphics

@testable import MBARCore
final class PolicyTests: XCTestCase {
    func testRestoreInvalidatesLateSuccessfulActivation() {
        var state = VisibilityState()
        let token = state.begin()
        XCTAssertEqual(state.phase, .activating)
        state.restore()
        state.finish(token, succeeded: true)
        XCTAssertEqual(state.phase, .visible)
        XCTAssertGreaterThan(state.generation, token)
    }
    func testFailedActivationRestoresAndNewAttemptCanSucceed() {
        var state = VisibilityState()
        let first = state.begin()
        state.finish(first, succeeded: false)
        XCTAssertEqual(state.phase, .visible)
        let next = state.begin()
        XCTAssertGreaterThan(next, first)
        state.finish(first, succeeded: true)
        XCTAssertEqual(state.phase, .activating)
        state.finish(next, succeeded: true)
        XCTAssertEqual(state.phase, .hidden)
    }
    func testHidesOnlySelectedThirdPartyAndAlwaysKeepsSelfAndSystem() {
        let result = MenuPolicy.allowed(running: ["a.app", "b.app", "com.apple.controlcenter"], hidden: ["a.app", "com.apple.controlcenter", "local.MBAR"], own: "local.MBAR")
        XCTAssertFalse(result.contains("a.app"))
        XCTAssertTrue(result.contains("b.app"))
        XCTAssertTrue(result.contains("local.MBAR"))
        XCTAssertTrue(result.contains("com.apple.controlcenter"))
        XCTAssertFalse(MenuPolicy.canHide("com.apple.SystemUIServer", own: "local.MBAR"))
        XCTAssertFalse(MenuPolicy.canHide("local.MBAR", own: "local.MBAR"))
    }
    func testPanelBelowAnchorAndInsideNegativeOriginScreen() {
        let screen = CGRect(x: -1920, y: -400, width: 1920, height: 1080)
        let anchor = CGRect(x: -40, y: 650, width: 25, height: 30)
        let frame = PanelLayout.frame(anchor: anchor, screen: screen, requested: CGSize(width: 400, height: 90))
        XCTAssertEqual(frame.maxY, anchor.minY - 8, accuracy: 0.01)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.width, 400)
    }
    func testOversizedPanelClampsToAvailableScreen() {
        let screen = CGRect(x: 100, y: 100, width: 320, height: 300)
        let frame = PanelLayout.frame(anchor: CGRect(x: 110, y: 375, width: 24, height: 25), screen: screen, requested: CGSize(width: 900, height: 800))
        XCTAssertTrue(screen.contains(frame))
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertLessThanOrEqual(frame.maxY, 367)
    }
}

import XCTest
import CoreGraphics
@testable import MBARCore
final class ClickGeometryTests: XCTestCase {
    func testNeverClicksAStaleOrMissingOrOffscreenTarget() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let valid = CGRect(x: 1000, y: 0, width: 24, height: 30)
        XCTAssertNil(ClickGeometry.point(first: nil, current: valid, screen: screen))
        XCTAssertNil(ClickGeometry.point(first: valid, current: valid.offsetBy(dx: 35, dy: 0), screen: screen))
        XCTAssertNil(ClickGeometry.point(first: valid.offsetBy(dx: 1100, dy: 0), current: valid.offsetBy(dx: 1100, dy: 0), screen: screen))
        let body = valid.offsetBy(dx: 0, dy: 200)
        XCTAssertNil(ClickGeometry.point(first: body, current: body, screen: screen))
    }
    func testClicksVerifiedCentreOnAnOffsetScreen() {
        let screen = CGRect(x: -1920, y: -500, width: 1920, height: 1080)
        let item = CGRect(x: -120, y: -500, width: 40, height: 30)
        XCTAssertEqual(ClickGeometry.point(first: item, current: item, screen: screen), CGPoint(x: -100, y: -485))
    }
    func testCollapsedNotchItemsSharingAnotherIconsSpaceCannotBeClicked() {
        // Observed macOS 27 geometry: Bob overlaps MBAR's chevron while folded.
        let screen = CGRect(x: -1512, y: 458, width: 1512, height: 982)
        let bob = CGRect(x: -628, y: 458, width: 38, height: 33)
        let mbar = CGRect(x: -634, y: 458, width: 44, height: 33)
        XCTAssertNil(ClickGeometry.point(first: bob, current: bob, screen: screen, occlusions: [mbar]))
    }
    func testAdjacentExpandedItemsRemainClickable() {
        let screen = CGRect(x: -1512, y: 458, width: 1512, height: 982)
        let bob = CGRect(x: -628, y: 458, width: 38, height: 33)
        let next = CGRect(x: bob.maxX, y: 458, width: 44, height: 33)
        XCTAssertEqual(ClickGeometry.point(first: bob, current: bob, screen: screen, occlusions: [next]), CGPoint(x: -609, y: 474.5))
    }

}

import XCTest
@testable import MBARCore

final class AppRelaunchTests: XCTestCase {
    func testOnlyValidExplicitRelaunchArgumentsAreAccepted() {
        let request = AppRelaunchRequest(arguments: ["MBAR", "--relaunch-parent", "123", "--reopen-icon-settings", "com.example.app"])
        XCTAssertEqual(request?.parentPID, 123)
        XCTAssertEqual(request?.iconBundle, "com.example.app")
        XCTAssertNil(AppRelaunchRequest(arguments: ["MBAR", "--relaunch-parent", "0"]))
        XCTAssertNil(AppRelaunchRequest(arguments: ["MBAR", "--relaunch-parent", "2147483648"]))
        XCTAssertNil(AppRelaunchRequest(arguments: ["MBAR", "--relaunch-parent", "123", "--reopen-icon-settings", "../somewhere"]))
        XCTAssertNil(AppRelaunchRequest(arguments: ["MBAR"]))
    }
}

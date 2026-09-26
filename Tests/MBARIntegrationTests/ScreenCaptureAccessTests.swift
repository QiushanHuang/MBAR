import XCTest
import ScreenCaptureKit
@testable import MBAR

final class ScreenCaptureAccessTests: XCTestCase {
    @MainActor func testStaleNegativePreflightDoesNotBlockActualAuthorizedRequest() async throws {
        let access = ScreenCaptureAccess(preflight: { false })
        var invoked = false
        let value = try await access.perform { invoked = true; return 42 }
        XCTAssertTrue(invoked)
        XCTAssertEqual(value, 42)
        XCTAssertEqual(access.lastPreflight, false)
        XCTAssertEqual(access.state, .allowed)
    }
    @MainActor func testDeniedRequestCanBeRetriedAfterConsentWithoutCachedBlock() async throws {
        let access = ScreenCaptureAccess(preflight: { true })
        do {
            _ = try await access.perform { () async throws -> Int in
                throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
            }
            XCTFail("Expected permission denial")
        } catch { XCTAssertTrue(ScreenCaptureAccess.isPermissionDenied(error)) }
        XCTAssertEqual(access.state, .needsSettings)
        let value = try await access.perform { 7 }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(access.state, .allowed)
    }
    @MainActor func testOtherFailuresAreNotMislabelledAsMissingPermission() async {
        let access = ScreenCaptureAccess(preflight: { true })
        do { _ = try await access.perform { () async throws -> Int in throw CocoaError(.fileReadUnknown) } }
        catch { XCTAssertFalse(ScreenCaptureAccess.isPermissionDenied(error)) }
        XCTAssertEqual(access.state, .failed)
    }
    @MainActor func testConstructionDoesNotRequestOrProbeScreenAccess() {
        var probed = false
        let access = ScreenCaptureAccess(preflight: { probed = true; return false })
        XCTAssertFalse(probed)
        XCTAssertEqual(access.state, .idle)
    }
    @MainActor func testWrappedPermissionErrorsAreRecognized() {
        let denied = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        let wrapped = NSError(domain: "MBAR", code: 1, userInfo: [NSUnderlyingErrorKey: denied])
        XCTAssertTrue(ScreenCaptureAccess.isPermissionDenied(wrapped))
    }
}

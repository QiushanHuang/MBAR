import XCTest
@testable import MBAR

@MainActor final class HidingServiceTests: XCTestCase {
    private final class Handle: NSObject {}
    private final class NativeSessions {
        var allowed: [[String]] = []
        var handles: [Handle] = []
        var callbacks: [(Error?) -> Void] = []
        var released: [ObjectIdentifier] = []
        var runtime: HidingRuntime {
            HidingRuntime(available: { true }, create: { allowed, callback in
                let handle = Handle()
                self.allowed.append(allowed); self.handles.append(handle); self.callbacks.append(callback)
                return handle
            }, release: { handle in
                if let handle { self.released.append(ObjectIdentifier(handle)) }
            })
        }
    }
    private func hide(_ service: HidingService, host: Int = 100) {
        service.hide(running: ["resident", "hidden"], selected: ["hidden"], own: "MBAR", hostPID: host)
    }
    private func complete(_ native: NativeSessions, _ service: HidingService, index: Int, error: Error? = nil) async {
        let changed = expectation(description: "native completion applied")
        service.onChange = { _, _ in changed.fulfill() }
        native.callbacks[index](error)
        await fulfillment(of: [changed], timeout: 1)
        service.onChange = nil
    }
    private func deliver(_ callback: (Error?) -> Void, error: Error? = nil) async {
        callback(error)
        // Native completions are marshalled onto the main queue. This FIFO
        // barrier observes their effects without a timing-dependent sleep.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    func testUnchangedRequestDoesNotRestartNativeAnimation() async {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        hide(service); await complete(native, service, index: 0)
        hide(service)
        XCTAssertEqual(native.allowed.count, 1)
        XCTAssertEqual(service.state.phase, .hidden)
        XCTAssertTrue(native.allowed[0].contains("resident"))
        XCTAssertFalse(native.allowed[0].contains("hidden"))
        service.restore()
    }
    func testReplacementHostGetsANewSessionEvenWithIdenticalBundles() async {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        hide(service); await complete(native, service, index: 0)
        hide(service, host: 101)
        XCTAssertEqual(native.allowed.count, 2, "A session belongs to a MenuBarAgent process, not just a bundle list")
        XCTAssertTrue(native.released.isEmpty, "Keep the previous protection until replacement succeeds")
        await complete(native, service, index: 1)
        XCTAssertEqual(native.released, [ObjectIdentifier(native.handles[0])])
        await deliver(native.callbacks[0])
        XCTAssertEqual(native.released, [ObjectIdentifier(native.handles[0])])
        XCTAssertEqual(service.state.phase, .hidden)
        service.restore()
    }
    func testSystemTransitionBlocksSubmissionsAndRebindsIdenticalRequestWhenSettled() async {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        hide(service); await complete(native, service, index: 0)
        service.suspendForSystemChange()
        hide(service)
        XCTAssertEqual(native.allowed.count, 1, "Never submit assertions against a sleeping or reconfiguring host")
        XCTAssertTrue(native.released.isEmpty)
        service.resumeAfterSystemChange()
        hide(service)
        XCTAssertEqual(native.allowed.count, 2, "The same PID and bundles still need rebinding after wake/display change")
        service.restore()
    }
    func testLateFailureDuringSleepCannotDisableHidingOrReleasePreviousProtection() async {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        hide(service); await complete(native, service, index: 0)
        hide(service, host: 101)
        service.suspendForSystemChange()
        var errors: [String] = []
        service.onChange = { _, error in if let error { errors.append(error) } }
        await deliver(native.callbacks[1], error: NSError(domain: "test", code: 1))
        XCTAssertTrue(errors.isEmpty, "A completion from the old environment must not change the user's enabled preference")
        XCTAssertTrue(native.released.isEmpty)
        service.resumeAfterSystemChange()
        hide(service, host: 101)
        XCTAssertEqual(native.allowed.count, 3)
        XCTAssertEqual(native.released, [ObjectIdentifier(native.handles[1])])
        service.restore()
    }
    func testInitialSuccessDuringTransitionCannotPublishStaleHiddenState() async {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        hide(service)
        service.suspendForSystemChange()
        await deliver(native.callbacks[0])
        XCTAssertEqual(service.state.phase, .activating)
        service.resumeAfterSystemChange()
        hide(service)
        XCTAssertEqual(native.allowed.count, 2)
        XCTAssertTrue(native.released.isEmpty, "A successful pending session must protect hidden items until its replacement succeeds")
        await complete(native, service, index: 1)
        XCTAssertEqual(service.state.phase, .hidden)
        XCTAssertEqual(native.released, [ObjectIdentifier(native.handles[0])])
        service.restore()
    }
    func testExplicitRestoreWhileSuspendedReleasesAllAndLateCallbackCannotResurrectIt() async {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        hide(service); await complete(native, service, index: 0)
        hide(service, host: 101)
        service.suspendForSystemChange()
        service.restore()
        XCTAssertEqual(Set(native.released), Set(native.handles.map(ObjectIdentifier.init)))
        service.resumeAfterSystemChange()
        await deliver(native.callbacks[1])
        XCTAssertEqual(service.state.phase, .visible)
        XCTAssertEqual(native.allowed.count, 2)
    }
    func testMissingHostCannotCreateANativeSession() {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        hide(service, host: 0)
        XCTAssertTrue(native.allowed.isEmpty)
        XCTAssertEqual(service.state.phase, .visible)
    }
    func testSleepCancelsPendingTemporaryRevealWithoutDroppingExistingProtection() async {
        let native = NativeSessions(), service = HidingService(runtime: native.runtime)
        let running: Set<String> = ["resident", "hidden", "other"]
        service.hide(running: running, selected: ["hidden", "other"], own: "MBAR", hostPID: 100)
        await complete(native, service, index: 0)
        service.hide(running: running, selected: ["other"], own: "MBAR", hostPID: 100)
        XCTAssertTrue(native.allowed[1].contains("hidden"))
        service.suspendForSystemChange()
        await deliver(native.callbacks[1])
        XCTAssertTrue(native.released.isEmpty, "A cancelled temporary reveal must not replace the restrictive active session")
        service.resumeAfterSystemChange()
        service.hide(running: running, selected: ["hidden", "other"], own: "MBAR", hostPID: 100)
        XCTAssertEqual(native.released, [ObjectIdentifier(native.handles[1])])
        await complete(native, service, index: 2)
        XCTAssertEqual(Set(native.released), Set(native.handles.prefix(2).map(ObjectIdentifier.init)))
        service.restore()
    }
}

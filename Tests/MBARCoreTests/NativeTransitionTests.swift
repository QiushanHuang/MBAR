import XCTest
@testable import MBARCore

final class NativeTransitionTests: XCTestCase {
    func testStableAXEndpointsDoNotImmediatelyEndNativeAnimation() {
        var gate = NativeTransitionGate(startedAt: 10)
        XCTAssertFalse(gate.observe(["host:A"], at: 10))
        XCTAssertFalse(gate.observe(["host:A"], at: 10.15))
        XCTAssertTrue(gate.observe(["host:A"], at: 10.6))
    }
    func testLateMovementRestartsQuietPeriod() {
        var gate = NativeTransitionGate(startedAt: 0)
        XCTAssertFalse(gate.observe(["x:10"], at: 0))
        XCTAssertFalse(gate.observe(["x:11"], at: 0.6))
        XCTAssertFalse(gate.observe(["x:11"], at: 0.7))
        XCTAssertTrue(gate.observe(["x:11"], at: 0.9))
    }
    func testMissingHostIsNotProofOfSettledLayout() {
        var gate = NativeTransitionGate(startedAt: 0)
        XCTAssertFalse(gate.observe([], at: 1))
        XCTAssertFalse(gate.observe(nil, at: 2))
        XCTAssertFalse(gate.observe(["host"], at: 3))
        XCTAssertTrue(gate.observe(["host"], at: 3.3))
    }
    func testOnlyOurOverflowExpansionIsRestored() {
        var lease = OverflowLease()
        let first = lease.claim()
        let second = lease.claim()
        XCTAssertFalse(lease.consume(first))
        XCTAssertTrue(lease.consume(second))
        XCTAssertFalse(lease.consume(second))
    }
}

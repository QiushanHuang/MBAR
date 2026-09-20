import XCTest
import CoreGraphics
@testable import MBARCore
final class HostedGeometryTests: XCTestCase {
    func testExpandedWindowWinsOverFoldedMirrorWithoutMixingTheirNeighbours() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let expanded = CGRect(x: 406.5, y: 0, width: 44, height: 33)
        let folded = CGRect(x: 868, y: 0, width: 44, height: 33)
        let samples = [HostedFrameSample(frame: folded, neighbours: [CGRect(x: 874, y: 0, width: 38, height: 33)]),
                       HostedFrameSample(frame: expanded, neighbours: [CGRect(x: 450.5, y: 0, width: 44, height: 33)])]
        XCTAssertEqual(HostedGeometry.resolve(samples, screen: screen), expanded)
    }
    func testContradictoryUnobscuredPositionsAreNotGuessed() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let a = CGRect(x: 400, y: 0, width: 40, height: 33)
        let b = CGRect(x: 600, y: 0, width: 40, height: 33)
        XCTAssertNil(HostedGeometry.resolve([.init(frame: a, neighbours: []), .init(frame: b, neighbours: [])], screen: screen))
        XCTAssertEqual(HostedGeometry.resolve([.init(frame: a, neighbours: []), .init(frame: a, neighbours: [])], screen: screen), a)
    }
}

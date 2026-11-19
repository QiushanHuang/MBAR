import XCTest
import MBARCore

final class ShelfLayoutTests: XCTestCase {
    func testThreePlacementsUseOpeningDisplaysUsableFrame() {
        let screen = CGRect(x: -2320, y: 155, width: 2210, height: 1230)
        let anchor = CGRect(x: -410, y: screen.maxY, width: 28, height: 30)
        let size = CGSize(width: 264, height: 320)
        for placement in ShelfPlacement.allCases {
            let frame = PanelLayout.frame(anchor: anchor, screen: screen, requested: size, placement: placement)
            XCTAssertTrue(screen.contains(frame))
            XCTAssertEqual(frame.maxY, screen.maxY - 8)
            switch placement {
            case .anchor: XCTAssertEqual(frame.maxX, anchor.maxX)
            case .left: XCTAssertEqual(frame.minX, screen.minX + 8)
            case .right: XCTAssertEqual(frame.maxX, screen.maxX - 8)
            }
        }
    }

    func testShelfExtendsLeftCenteredOrRightUnderEntry() {
        let screen = CGRect(x: -1920, y: 240, width: 1920, height: 1050)
        let entry = CGRect(x: -958, y: screen.maxY, width: 28, height: 30)
        let size = CGSize(width: 270, height: 110)
        for alignment in ShelfAlignment.allCases {
            let frame = PanelLayout.frame(anchor: entry, screen: screen, requested: size, alignment: alignment)
            switch alignment {
            case .left: XCTAssertEqual(frame.maxX, entry.maxX)
            case .center: XCTAssertEqual(frame.midX, entry.midX)
            case .right: XCTAssertEqual(frame.minX, entry.minX)
            }
            XCTAssertEqual(frame.maxY, entry.minY - 8)
            XCTAssertEqual(frame.size, size)
            let left = PanelLayout.frame(anchor: entry, screen: screen, requested: size, placement: .left, alignment: alignment)
            let right = PanelLayout.frame(anchor: entry, screen: screen, requested: size, placement: .right, alignment: alignment)
            XCTAssertEqual(left.minX, screen.minX + 8)
            XCTAssertEqual(right.maxX, screen.maxX - 8)
        }
    }

    func testAlignedShelfClampsToDisplayEdgesIncludingUnavailableEntry() {
        let usable = CGRect(x: 468, y: -300, width: 1380, height: 870)
        let display = CGRect(x: 420, y: -300, width: 1428, height: 900)
        let fallback = PanelLayout.fallbackAnchor(display: display, usable: usable, menuBarHeight: 30)
        let leftEntry = CGRect(x: usable.minX, y: usable.maxY, width: 28, height: 30)
        for alignment in ShelfAlignment.allCases {
            let size = CGSize(width: 352, height: 112)
            let atLeft = PanelLayout.frame(anchor: leftEntry, screen: usable, requested: size, alignment: alignment)
            let atRight = PanelLayout.frame(anchor: fallback, screen: usable, requested: size, alignment: alignment)
            XCTAssertEqual(atLeft.minX, usable.minX + 8)
            XCTAssertEqual(atRight.maxX, usable.maxX - 8)
            XCTAssertEqual(atRight.size, size)
        }
    }

    func testOffscreenHostedWindowFallsBackToMenuBarOrActualClick() throws {
        let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let usable = CGRect(x: 0, y: 0, width: 2560, height: 1410)
        let placeholder = CGRect(x: 7, y: -12, width: 30, height: 24)
        XCTAssertFalse(PanelLayout.isMenuBarAnchor(placeholder, on: display))
        let fallback = PanelLayout.fallbackAnchor(display: display, usable: usable, menuBarHeight: 24)
        let size = CGSize(width: 208, height: 102)
        let frame = PanelLayout.frame(anchor: fallback, screen: usable, requested: size, placement: .left)
        XCTAssertEqual(frame.size, size)
        XCTAssertEqual(frame.maxY, usable.maxY - 8)
        let anchor = try XCTUnwrap(PanelLayout.clickedAnchor(point: CGPoint(x: 900, y: 1420), display: display,
                                                             usable: usable, menuBarHeight: 24))
        XCTAssertEqual(anchor.midX, 900)
        XCTAssertEqual(anchor.minY, 1410)
        XCTAssertNil(PanelLayout.clickedAnchor(point: CGPoint(x: 900, y: 700), display: display, usable: usable, menuBarHeight: 24))
    }

    func testGridFitsNarrowDisplayAndLargeCollectionsScrollWithinBounds() {
        let available = CGSize(width: 200, height: 240)
        let items = Array(repeating: CGFloat(28), count: 50)
        for style in ShelfStyle.allCases {
            let size = ShelfMetrics.size(style: style, itemWidths: items, available: available, showsLock: true)
            XCTAssertLessThanOrEqual(size.width, available.width)
            XCTAssertLessThanOrEqual(size.height, available.height)
            XCTAssertEqual(size.height, style == .strip ? ShelfMetrics.height : available.height)
        }
        XCTAssertEqual(ShelfMetrics.gridColumns(for: 200, itemCount: 50), 2)
        XCTAssertEqual(ShelfMetrics.gridColumns(for: 700, itemCount: 50), 4)
        XCTAssertEqual(ShelfMetrics.gridColumns(for: 200, itemCount: 0), 1)
    }
}

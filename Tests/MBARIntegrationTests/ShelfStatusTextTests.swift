import AppKit
import XCTest
@testable import MBAR

final class ShelfStatusTextTests: XCTestCase {
    @MainActor func testReadsLegacyAndCurrentClashSpeedLabels() {
        XCTAssertEqual(ShelfStatusText.rateLines(" ↑ 1.2 KB/s | ↓ 23 B/s "), ["↑ 1.2 KB/s", "↓ 23 B/s"])
        XCTAssertEqual(ShelfStatusText.rateLines("  20K/s\n 7.4M/s"), ["20K/s", "7.4M/s"])
        XCTAssertEqual(ShelfStatusText.rateLines("8GiB/s"), ["8GiB/s"])
    }

    @MainActor func testUnavailableOrUnrecognisedStatusProducesNoOverlay() {
        for title in ["", "Clash Verge", "Profile: 17 KB/s", "5 KB/s | stale", "1B/s|2B/s|3B/s"] {
            XCTAssertTrue(ShelfStatusText.rateLines(title).isEmpty, title)
        }
    }
}

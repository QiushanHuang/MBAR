import XCTest
@testable import MBARCore

final class ShelfOrderingTests: XCTestCase {
    func testEnumerationOrderDoesNotChangeSharedShelfOrder() {
        let items = [ShelfOrderKey(name: "Tailscale", id: "tail#0"),
                     ShelfOrderKey(name: "ChatGPT", id: "chat#0"),
                     ShelfOrderKey(name: "BuhoNTFS", id: "buho#0")]
        let expected = ["buho#0", "chat#0", "tail#0"]
        for input in [items, Array(items.reversed()), [items[1], items[2], items[0]]] {
            XCTAssertEqual(input.sorted().map(\.id), expected)
        }
    }
    func testSameNamedItemsHaveDeterministicNaturalOrder() {
        let items = [ShelfOrderKey(name: "Widget", id: "app#10"),
                     ShelfOrderKey(name: "Widget", id: "app#2"),
                     ShelfOrderKey(name: "Widget", id: "app#0")]
        XCTAssertEqual(items.sorted().map(\.id), ["app#0", "app#2", "app#10"])
    }
}

import AppKit
import XCTest
@testable import MBAR

final class ShelfFocusTests: XCTestCase {
    @MainActor func testTabAndShiftTabFollowVisibleOrderAndWrap() throws {
        let (window, buttons, focus) = makeShelf()
        let first = buttons[0], second = buttons[1], last = buttons[2]
        focus.register(last, order: 2)
        focus.register(first, order: 0)
        focus.register(second, order: 1)
        XCTAssertTrue(window.makeFirstResponder(first))

        first.keyDown(with: try tabEvent(window: window))
        XCTAssertTrue(window.firstResponder === second)
        second.keyDown(with: try tabEvent(window: window))
        XCTAssertTrue(window.firstResponder === last)
        last.keyDown(with: try tabEvent(window: window))
        XCTAssertTrue(window.firstResponder === first)
        first.keyDown(with: try tabEvent(window: window, backwards: true))
        XCTAssertTrue(window.firstResponder === last)
    }

    @MainActor func testDisabledAndRemovedControlsAreSkipped() throws {
        let (window, buttons, focus) = makeShelf()
        for (index, button) in buttons.enumerated() { focus.register(button, order: index) }
        buttons[1].isEnabled = false
        XCTAssertTrue(window.makeFirstResponder(buttons[0]))

        buttons[0].keyDown(with: try tabEvent(window: window))
        XCTAssertTrue(window.firstResponder === buttons[2])
        focus.unregister(buttons[2])
        XCTAssertTrue(window.makeFirstResponder(buttons[0]))
        buttons[0].keyDown(with: try tabEvent(window: window))
        XCTAssertTrue(window.firstResponder === buttons[0])
    }

    @MainActor private func makeShelf() -> (NSWindow, [ShelfButton], ShelfFocusCoordinator) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let focus = ShelfFocusCoordinator()
        let buttons = (0..<3).map { _ in ShelfButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28)) }
        for button in buttons {
            button.focusCoordinator = focus
            window.contentView?.addSubview(button)
        }
        return (window, buttons, focus)
    }

    private func tabEvent(window: NSWindow, backwards: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: backwards ? [.shift] : [],
                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    }
}

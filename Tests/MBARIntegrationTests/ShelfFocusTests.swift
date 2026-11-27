import AppKit
import SwiftUI
import MBARCore
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

    @MainActor func testGridArrowsKeepTheColumnAndReachShortRowsAndFooter() throws {
        let (window, buttons, focus) = makeShelf(count: 7)
        for (index, button) in buttons.enumerated() {
            // Four tiles, one tile on the next row, then two footer buttons.
            let row = index < 4 ? 0 : (index == 4 ? 1 : 2)
            let column = index < 4 ? index : (index == 4 ? 0 : index - 3)
            focus.register(button, order: index, row: row, column: column)
        }
        XCTAssertTrue(window.makeFirstResponder(buttons[3]))
        buttons[3].keyDown(with: try keyEvent(window: window, keyCode: 125))
        XCTAssertTrue(window.firstResponder === buttons[4])
        buttons[4].keyDown(with: try keyEvent(window: window, keyCode: 125))
        XCTAssertTrue(window.firstResponder === buttons[5])
        buttons[5].keyDown(with: try keyEvent(window: window, keyCode: 124))
        XCTAssertTrue(window.firstResponder === buttons[6])
        buttons[6].keyDown(with: try keyEvent(window: window, keyCode: 126))
        XCTAssertTrue(window.firstResponder === buttons[4])
        buttons[4].keyDown(with: try keyEvent(window: window, keyCode: 126))
        XCTAssertTrue(window.firstResponder === buttons[0])
    }

    @MainActor func testLayoutsExposeOffscreenItemsAndKeepToolsOutsideTheScrollView() throws {
        _ = NSApplication.shared
        let suite = "MBAR.ShelfFocusTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(iconLibrary: IconLibrary(directory: directory), defaults: defaults)
        model.items = (1...25).map { index in
            let name = String(format: "App %02d", index)
            return MenuItem(id: name, bundle: name, name: name, title: name, pid: getpid(),
                            element: AXUIElementCreateApplication(getpid()), frame: nil)
        }
        model.policy = ShelfPolicy(assignments: Dictionary(uniqueKeysWithValues: model.items.map { ($0.bundle, .automatic) }))
        model.selectShelfPreset("apple-glass")
        for style in ShelfStyle.allCases {
            model.shelfStyle = style
            let size = ShelfMetrics.size(style: style, itemWidths: Array(repeating: 28, count: model.items.count),
                                         available: CGSize(width: 400, height: 175), showsLock: true)
            let window = ShelfPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            let host = ShelfHostingView(rootView: ShelfView(model: model, width: size.width, height: size.height))
            window.contentView = host
            window.setFrameOrigin(CGPoint(x: -16000, y: -16000))
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let buttons = shelfButtons(in: host)
            let first = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == "App 01" })
            let last = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == "App 25" })
            let gear = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == "MBAR 设置" })
            XCTAssertNil(gear.enclosingScrollView)
            window.recalculateKeyViewLoop()
            XCTAssertTrue(window.makeFirstResponder(host))
            window.sendEvent(try tabEvent(window: window))
            XCTAssertTrue(window.firstResponder === first, "First Tab should enter the first item; got \(String(describing: window.firstResponder))")
            // The first Shift-Tab wraps to the gear, then lock, then the last item.
            first.keyDown(with: try tabEvent(window: window, backwards: true))
            XCTAssertTrue(window.firstResponder === gear)
            gear.keyDown(with: try tabEvent(window: window, backwards: true))
            let lock = try XCTUnwrap(window.firstResponder as? ShelfButton)
            lock.keyDown(with: try tabEvent(window: window, backwards: true))
            XCTAssertTrue(window.firstResponder === last)
            XCTAssertFalse(last.visibleRect.isEmpty)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let hit = host.hitTest(last.convert(CGPoint(x: last.bounds.midX, y: last.bounds.midY), to: host.superview))
            XCTAssertTrue(hit === last, "Expected last item; got \(String(describing: hit)), bounds=\(last.bounds) last=\(last.visibleRect) center=\(last.convert(NSZeroPoint, to: host)).")
            last.keyDown(with: try keyEvent(window: window, keyCode: 36))
            XCTAssertEqual(model.iconSettingsBundle, "App 25")
            model.iconSettingsBundle = nil

            model.shelfToolsSide = .left
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let reordered = shelfButtons(in: host)
            let leftLock = try XCTUnwrap(reordered.first { $0.accessibilityLabel() == "锁定下拉栏" })
            let leftGear = try XCTUnwrap(reordered.first { $0.accessibilityLabel() == "MBAR 设置" })
            let firstApp = try XCTUnwrap(reordered.first { $0.accessibilityLabel() == "App 01" })
            XCTAssertNil(leftGear.enclosingScrollView)
            let lockFrame = leftLock.convert(leftLock.bounds, to: host)
            let gearFrame = leftGear.convert(leftGear.bounds, to: host)
            XCTAssertEqual(lockFrame.minX, style == .strip ? ShelfMetrics.stripInset : ShelfMetrics.bodyInset, accuracy: 0.5)
            XCTAssertLessThan(lockFrame.maxX, gearFrame.minX)
            window.makeFirstResponder(host)
            window.sendEvent(try tabEvent(window: window))
            XCTAssertTrue(window.firstResponder === (style == .strip ? leftLock : firstApp))
            window.makeFirstResponder(leftLock)
            leftLock.keyDown(with: try keyEvent(window: window, keyCode: 124))
            XCTAssertTrue(window.firstResponder === leftGear)
            leftGear.keyDown(with: try tabEvent(window: window))
            XCTAssertTrue(window.firstResponder === firstApp)

            model.setShowsShelfLock(false)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let compact = shelfButtons(in: host)
            XCTAssertFalse(compact.contains { $0.accessibilityLabel() == "锁定下拉栏" })
            let solo = try XCTUnwrap(compact.first { $0.accessibilityLabel() == "MBAR 设置" })
            XCTAssertEqual(solo.convert(solo.bounds, to: host).minX, lockFrame.minX, accuracy: 0.5)
            XCTAssertTrue(window.makeFirstResponder(solo))
            solo.keyDown(with: try tabEvent(window: window))
            XCTAssertTrue((window.firstResponder as? ShelfButton)?.accessibilityLabel() == "App 01")
            model.setShowsShelfLock(true)
            model.shelfToolsSide = .right
        }
    }

    @MainActor private func shelfButtons(in view: NSView) -> [ShelfButton] {
        if let button = view as? ShelfButton { return [button] }
        return view.subviews.flatMap(shelfButtons(in:))
    }

    private func keyEvent(window: NSWindow, keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
    }

    @MainActor private func makeShelf(count: Int = 3) -> (NSWindow, [ShelfButton], ShelfFocusCoordinator) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let focus = ShelfFocusCoordinator()
        let buttons = (0..<count).map { _ in ShelfButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28)) }
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

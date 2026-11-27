import AppKit
import MBARCore
import SwiftUI
import XCTest
@testable import MBAR

final class ShelfAppearanceEditorTests: XCTestCase {
    @MainActor func testChangingPresetInOpenEditorMovesSliderAndKeyboardEditsOnlyWorkingCopy() throws {
        _ = NSApplication.shared
        let id = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: id))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        defer { defaults.removePersistentDomain(forName: id); try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(iconLibrary: IconLibrary(directory: directory), defaults: defaults)
        let host = NSHostingView(rootView: ShelfAppearanceSettings(model: model))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 500, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        func layout() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
        func sliders(_ view: NSView) -> [NSSlider] {
            if let slider = view as? NSSlider { return [slider] }
            return view.subviews.flatMap(sliders)
        }
        layout()
        XCTAssertEqual(model.shelfAppearance.intensity, 0)
        model.selectShelfPreset("lagoon")
        layout()
        let slider = try XCTUnwrap(sliders(host).first)
        XCTAssertEqual(slider.doubleValue, 0.65, accuracy: 0.001)
        XCTAssertEqual(model.shelfAppearance.intensity, 0.65, accuracy: 0.001)
        XCTAssertTrue(window.makeFirstResponder(slider))
        let right = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                   characters: "\u{f703}", charactersIgnoringModifiers: "\u{f703}",
                                                   isARepeat: false, keyCode: 124))
        slider.keyDown(with: right)
        XCTAssertEqual(model.shelfAppearance.intensity, 0.66, accuracy: 0.001)
        model.selectShelfPreset("lagoon")
        layout()
        XCTAssertEqual(slider.doubleValue, 0.65, accuracy: 0.001)
        XCTAssertFalse(sliders(host).contains { $0.accessibilityLabel() == "磨砂强度" })
        model.selectShelfPreset("apple-glass")
        layout()
        let frost = try XCTUnwrap(sliders(host).first { $0.accessibilityLabel() == "磨砂强度" })
        XCTAssertEqual(frost.doubleValue, 0.35, accuracy: 0.001)
        frost.keyDown(with: right)
        XCTAssertEqual(model.shelfAppearance.frostAmount, 0.36, accuracy: 0.001)
        XCTAssertEqual(model.shelfAppearance.intensity, 0)
        model.selectShelfPreset("quiet-glass")
        layout()
        let quietFrost = try XCTUnwrap(sliders(host).first { $0.accessibilityLabel() == "磨砂强度" })
        XCTAssertEqual(quietFrost.doubleValue, model.shelfAppearance.frostAmount, accuracy: 0.001)
        quietFrost.keyDown(with: right)
        XCTAssertEqual(model.shelfAppearance.frostAmount, 0.58, accuracy: 0.001)
    }
}

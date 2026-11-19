import AppKit
import MBARCore
import XCTest
@testable import MBAR

final class ShelfBackdropTests: XCTestCase {
    @MainActor func testClearGlassSuppressesOnlyTheFloatingShelfsWindowShadow() throws {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 220, height: 40)
        let clear = try XCTUnwrap(ShelfAppearancePreset.builtIns.first { $0.id == "apple-glass" }).appearance
        let frost = try XCTUnwrap(ShelfAppearancePreset.builtIns.first { $0.id == "frost" }).appearance
        let panel = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.hasShadow = true
        let backdrop = ShelfBackdrop(frame: frame, configuration: clear, content: NSView())
        panel.contentView = backdrop
        if #available(macOS 26, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            XCTAssertFalse(panel.hasShadow)
            backdrop.apply(frost)
            XCTAssertTrue(panel.hasShadow)
            backdrop.apply(clear)
            XCTAssertFalse(panel.hasShadow)
        }
        let preview = ShelfBackdrop(frame: frame, configuration: clear, content: NSView(), blendingMode: .withinWindow)
        let editor = NSWindow(contentRect: frame, styleMask: .titled, backing: .buffered, defer: false)
        editor.hasShadow = true
        editor.contentView = preview
        preview.apply(frost)
        preview.apply(clear)
        XCTAssertTrue(editor.hasShadow)
    }

    @MainActor func testTranslucentOpacityChangesOnlyTheBackdrop() throws {
        _ = NSApplication.shared
        let content = NSView()
        var appearance = ShelfAppearance(material: .translucent, tint: .init(red: 0.2, green: 0.6, blue: 0.8),
                                         intensity: 0.8, opacity: 0.25)
        let backdrop = ShelfBackdrop(frame: CGRect(x: 0, y: 0, width: 200, height: 42),
                                     configuration: appearance, content: content)
        let accessibility = NSWorkspace.shared
        let opaque = accessibility.accessibilityDisplayShouldReduceTransparency || accessibility.accessibilityDisplayShouldIncreaseContrast
        let panelColor = try XCTUnwrap(backdrop.subviews.first?.layer?.backgroundColor)
        XCTAssertEqual(panelColor.alpha, opaque ? 1 : 0.25, accuracy: 0.01)
        XCTAssertEqual(content.alphaValue, 1)
        if !opaque { XCTAssertNotNil(content.shadow) }
        appearance.opacity = 1
        backdrop.apply(appearance)
        let solidColor = try XCTUnwrap(backdrop.subviews.first?.layer?.backgroundColor)
        XCTAssertEqual(solidColor.alpha, 1, accuracy: 0.01)
        XCTAssertNil(content.shadow)
    }

    @MainActor func testSwitchingMaterialKeepsContentSizeFocusAndHitTargets() throws {
        _ = NSApplication.shared
        let size = NSSize(width: 220, height: 42)
        let panel = ShelfPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: .aqua)
        let content = NSView()
        let button = ShelfButton(frame: NSRect(x: 32, y: 6, width: 30, height: 30))
        content.addSubview(button)
        let presets = ShelfAppearancePreset.builtIns
        let backdrop = ShelfBackdrop(frame: NSRect(origin: .zero, size: size),
                                     configuration: presets[0].appearance, content: content)
        panel.contentView = backdrop
        XCTAssertTrue(panel.makeFirstResponder(button))
        // Return to regular glass after the last variant to exercise appearance restoration.
        for preset in presets + presets.filter({ $0.appearance.material == .liquid }).prefix(1) {
            backdrop.apply(preset.appearance)
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(content.bounds.size, size, preset.name)
            XCTAssertTrue(panel.firstResponder === button, preset.name)
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: backdrop.superview)
            XCTAssertTrue(backdrop.hitTest(point) === button, preset.name)
            let isClear = preset.appearance.material == .appleGlass
            if #available(macOS 26, *), isClear || preset.appearance.material == .liquid,
               !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                if isClear {
                    let optics = try XCTUnwrap(backdrop.subviews.first as? ClearShelfGlass)
                    XCTAssertEqual(optics.glass.style, .clear)
                    XCTAssertNil(optics.glass.hitTest(.zero))
                    XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
                    XCTAssertNotNil(content.shadow)
                } else {
                    let regular = try XCTUnwrap(backdrop.subviews.first as? NSGlassEffectView)
                    XCTAssertEqual(regular.style, .regular)
                    XCTAssertTrue(regular.contentView === content)
                    XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
                    XCTAssertNil(content.shadow)
                }
            }
        }
    }
}

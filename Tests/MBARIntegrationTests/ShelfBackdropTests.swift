import AppKit
import MBARCore
import XCTest
@testable import MBAR

final class ShelfBackdropTests: XCTestCase {
    @MainActor func testEveryMaterialKeepsTheReferenceCornersAsTheShelfResizes() throws {
        _ = NSApplication.shared
        let panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        var appearance = ShelfAppearancePreset.builtIns[0].appearance
        let backdrop = ShelfBackdrop(frame: .zero, configuration: appearance, content: NSView())
        panel.contentView = backdrop
        let layouts = ShelfStyle.allCases.map {
            ShelfMetrics.size(style: $0, itemWidths: [24, 30, 24, 24, 24], available: CGSize(width: 800, height: 600), showsLock: true)
        }
        for material in ShelfMaterial.allCases {
            appearance.material = material
            backdrop.apply(appearance)
            for size in layouts + [CGSize(width: 120, height: 24)] {
                panel.setContentSize(size)
                backdrop.layoutSubtreeIfNeeded()
                let expected: CGFloat = size.height == 24 ? 12 : 16
                let layer = try XCTUnwrap(backdrop.layer)
                XCTAssertEqual(layer.cornerRadius, expected, "\(material) \(size)")
                XCTAssertEqual(layer.cornerCurve, .continuous)
                XCTAssertTrue(layer.masksToBounds)
                let surface = try XCTUnwrap(backdrop.subviews.first)
                if backdrop.content.isDescendant(of: surface) {
                    XCTAssertEqual(surface.layer?.cornerRadius ?? 0, 0, "Foreground corners must be clipped only once")
                } else {
                    XCTAssertTrue(backdrop.content.superview === backdrop)
                }
                if let frost = surface as? NSVisualEffectView {
                    XCTAssertEqual(frost.layer?.cornerRadius, expected)
                    XCTAssertEqual(frost.maskImage?.capInsets.top, expected)
                }
                if #available(macOS 26, *), let glass = (surface as? ClearShelfGlass)?.glass ?? surface as? NSGlassEffectView {
                    XCTAssertEqual(glass.cornerRadius, expected)
                }
            }
        }
    }

    @MainActor func testQuietGlassKeepsNativeGlassNonKeyAndRetainsTheShelfControls() throws {
        guard #available(macOS 26, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Requires native transparent glass.")
        }
        let frame = NSRect(x: -3000, y: -3000, width: 220, height: 36)
        for mode: NSVisualEffectView.BlendingMode in [.behindWindow, .withinWindow] {
            let owner = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let content = NSView()
            var appearance = try XCTUnwrap(ShelfAppearancePreset.builtIns.first { $0.id == "quiet-glass" }).appearance
            let backdrop = ShelfBackdrop(frame: .init(origin: .zero, size: frame.size), configuration: appearance,
                                         content: content, blendingMode: mode)
            owner.contentView = backdrop
            owner.orderFrontRegardless()
            defer { owner.orderOut(nil) }
            backdrop.layoutSubtreeIfNeeded()
            let opticsWindow = try XCTUnwrap(owner.childWindows?.first)
            XCTAssertFalse(opticsWindow.canBecomeKey)
            XCTAssertFalse(opticsWindow.canBecomeMain)
            XCTAssertTrue(opticsWindow.ignoresMouseEvents)
            XCTAssertFalse(opticsWindow.hasShadow)
            XCTAssertTrue(content.window === (mode == .behindWindow ? owner : opticsWindow))
            func findGlass(in view: NSView) -> ClearShelfGlass? {
                if let glass = view as? ClearShelfGlass { return glass }
                return view.subviews.lazy.compactMap(findGlass).first
            }
            let optics = try XCTUnwrap(findGlass(in: XCTUnwrap(opticsWindow.contentView)))
            XCTAssertEqual(optics.glass.style, .clear)
            XCTAssertEqual(optics.frostAmount, appearance.frostAmount)
            XCTAssertEqual(optics.glass.cornerRadius, 16)
            appearance.frostAmount = 0.82
            appearance.intensity = 0
            backdrop.apply(appearance)
            XCTAssertEqual(optics.frostAmount, 0.82)
            XCTAssertNil(optics.glass.tintColor)
            owner.setContentSize(NSSize(width: 330, height: 64))
            backdrop.layoutSubtreeIfNeeded()
            XCTAssertEqual(opticsWindow.frame, owner.convertToScreen(backdrop.convert(backdrop.bounds, to: nil)))

            owner.orderOut(nil)
            XCTAssertFalse(opticsWindow.isVisible)
            owner.orderFrontRegardless()
            XCTAssertTrue(opticsWindow.isVisible)
            appearance.material = .appleGlass
            backdrop.apply(appearance)
            XCTAssertNil(opticsWindow.parent)
            XCTAssertFalse(opticsWindow.isVisible)
            XCTAssertTrue(content.window === owner)
        }
    }

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

    @MainActor func testSystemInkInheritsWindowAppearanceWhileGlassKeepsItsCalibration() throws {
        guard #available(macOS 26, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Requires clear glass.")
        }
        let frame = NSRect(x: 0, y: 0, width: 200, height: 38)
        let window = NSPanel(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        var appearance = try XCTUnwrap(ShelfAppearancePreset.builtIns.first { $0.id == "apple-glass" }).appearance
        let content = NSView()
        let backdrop = ShelfBackdrop(frame: frame, configuration: appearance, content: content)
        window.contentView = backdrop
        appearance.iconTreatment = .system
        backdrop.apply(appearance)
        for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua] {
            window.appearance = NSAppearance(named: name)
            XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
            let optics = try XCTUnwrap(backdrop.subviews.first as? ClearShelfGlass)
            XCTAssertEqual(optics.glass.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        }
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
                    XCTAssertNil(content.shadow)
                } else {
                    let regular = try XCTUnwrap(backdrop.subviews.first as? NSGlassEffectView)
                    XCTAssertEqual(regular.style, .regular)
                    XCTAssertFalse(content.isDescendant(of: regular))
                    XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
                    XCTAssertNil(content.shadow)
                }
            }
        }
    }
}

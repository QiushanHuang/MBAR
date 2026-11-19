import AppKit
import MBARCore
import SwiftUI
import XCTest
@testable import MBAR

final class ShelfContentLayoutTests: XCTestCase {
    @MainActor private func descendant<T: NSView>(_ type: T.Type, in parent: NSView) -> T? {
        if let match = parent as? T { return match }
        return parent.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }

    @MainActor private func withModel(_ verify: (AppModel) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: folder.lastPathComponent))
        defer {
            defaults.removePersistentDomain(forName: folder.lastPathComponent)
            try? FileManager.default.removeItem(at: folder)
        }
        _ = NSApplication.shared
        let model = AppModel(iconLibrary: IconLibrary(directory: folder), defaults: defaults)
        try verify(model)
    }

    @MainActor func testPreviewFillsGlassWhenChangingMaterial() throws {
        try withModel(verifyPreview)
    }

    @MainActor private func verifyPreview(_ model: AppModel) throws {
        let editor = NSHostingView(rootView: ShelfAppearanceSettings(model: model))
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 500, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for material: ShelfMaterial in [.frosted, .appleGlass, .liquid, .appleGlass, .translucent, .appleGlass] {
            var appearance = model.shelfAppearance
            appearance.material = material
            model.setShelfAppearance(appearance)
            editor.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
            let backdrop = try XCTUnwrap(descendant(ShelfBackdrop.self, in: editor))
            let host = backdrop.content
            let frame = host.convert(host.bounds, to: backdrop)
            XCTAssertEqual(frame, backdrop.bounds, "Preview host must occupy its rendered material for \(material)")
        }
    }

    @MainActor func testFloatingShelfKeepsControlsInsideResizedGlass() throws {
        try withModel { model in
            let startSize = CGSize(width: 208, height: ShelfMetrics.height)
            let frame = NSRect(origin: CGPoint(x: -3000, y: -3000), size: startSize)
            let panel = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            let host = ShelfHostingView(rootView: ShelfView(model: model, width: frame.width, height: frame.height))
            let backdrop = ShelfBackdrop(frame: CGRect(origin: .zero, size: startSize),
                                         configuration: model.shelfAppearance, content: host)
            panel.contentView = backdrop
            panel.orderFrontRegardless()
            defer { panel.orderOut(nil) }
            for (material, width): (ShelfMaterial, CGFloat) in [(.liquid, 208), (.appleGlass, 288), (.translucent, 184), (.appleGlass, 242)] {
                var appearance = model.shelfAppearance
                appearance.material = material
                backdrop.apply(appearance)
                host.rootView = ShelfView(model: model, width: width, height: startSize.height)
                panel.setContentSize(CGSize(width: width, height: startSize.height))
                panel.contentView?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                XCTAssertEqual(host.convert(host.bounds, to: backdrop), backdrop.bounds)
                let button = try XCTUnwrap(allButtons(in: host).first { $0.accessibilityLabel() == "MBAR 设置" })
                let target = button.convert(button.bounds, to: backdrop)
                XCTAssertEqual(target.midY, backdrop.bounds.midY, accuracy: 0.5)
                XCTAssertEqual(backdrop.bounds.maxX - target.maxX, ShelfMetrics.stripInset, accuracy: 0.5)
            }
        }
    }

    @MainActor func testStripPaintsWideArtworkAtItsPointSizeWithEdgeClearance() throws {
        try withModel { model in
            let item = MenuItem(id: "wide", bundle: "layout.fixture", name: "Wide", title: "Wide",
                                pid: getpid(), element: AXUIElementCreateApplication(getpid()), frame: nil)
            model.items = [item]
            model.policy = ShelfPolicy(assignments: [item.bundle: .automatic])
            model.selectShelfPreset("apple-glass")
            // Include a 26pt native crop from a tall menu bar alongside the usual 24pt image.
            for (height, scale): (CGFloat, Double) in [(24, 0.70), (24, 1), (24, 1.50), (26, 1), (26, 1.50)] {
                let sourceSize = CGSize(width: 2 * height, height: height)
                model.previews[item.id] = NSImage(size: sourceSize, flipped: false) { rect in
                    NSColor.red.setFill()
                    NSBezierPath.fill(rect)
                    return true
                }
                model.shelfIconScale = scale
                for side in ShelfToolsSide.allCases {
                    model.shelfToolsSide = side
                    let size = ShelfMetrics.size(style: .strip, itemWidths: [model.previewWidth(for: item)],
                                                 available: CGSize(width: 500, height: 100), showsLock: true,
                                                 scale: scale, tallestGlyphHeight: model.shelfMaxGlyphHeight)
                    let frame = CGRect(origin: CGPoint(x: -3000, y: -3000), size: size)
                    let panel = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    let host = ShelfHostingView(rootView: ShelfView(model: model, width: size.width, height: size.height))
                    panel.contentView = ShelfBackdrop(frame: CGRect(origin: .zero, size: size),
                                                      configuration: model.shelfAppearance, content: host)
                    panel.orderFrontRegardless()
                    defer { panel.orderOut(nil) }
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                    let painted = try redBounds(in: host)
                    XCTAssertEqual(painted.width, sourceSize.width * scale, accuracy: 1, "\(scale), \(side)")
                    XCTAssertEqual(painted.height, sourceSize.height * scale, accuracy: 1)
                    XCTAssertEqual(painted.midY, size.height / 2, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(painted.minX, ShelfMetrics.stripInset)
                    XCTAssertGreaterThanOrEqual(size.width - painted.maxX, ShelfMetrics.stripInset)
                    XCTAssertGreaterThanOrEqual(min(painted.minY, size.height - painted.maxY), 5)
                }
            }
        }
    }

    @MainActor private func redBounds(in view: NSView) throws -> CGRect {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var pixels = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.75, color.redComponent > 0.65,
                      color.redComponent - max(color.greenComponent, color.blueComponent) > 0.45 else { continue }
                pixels = pixels.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let painted = try XCTUnwrap(pixels.isNull ? nil : pixels, "The shelf should draw the synthetic red artwork.")
        return painted.applying(CGAffineTransform(scaleX: view.bounds.width / CGFloat(bitmap.pixelsWide),
                                                  y: view.bounds.height / CGFloat(bitmap.pixelsHigh)))
    }

    @MainActor private func allButtons(in view: NSView) -> [ShelfButton] {
        if let button = view as? ShelfButton { return [button] }
        return view.subviews.flatMap(allButtons(in:))
    }
}

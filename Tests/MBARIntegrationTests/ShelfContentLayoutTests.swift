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
                XCTAssertEqual(backdrop.bounds.maxX - target.maxX, 4, accuracy: 0.5)
            }
        }
    }

    @MainActor private func allButtons(in view: NSView) -> [ShelfButton] {
        if let button = view as? ShelfButton { return [button] }
        return view.subviews.flatMap(allButtons(in:))
    }
}

import AppKit
import MBARCore
import ScreenCaptureKit
import XCTest
@testable import MBAR

final class QuietGlassRenderingTests: XCTestCase {
    /// Exercise WindowServer's native glass using only windows owned by this test.
    @MainActor func testFocusedQuietShelfMatchesOriginalWhileSettingsIsKey() async throws {
        guard ProcessInfo.processInfo.environment["MBAR_TEST_GLASS_OPTICS"] == "1" else {
            throw XCTSkip("Opt-in visual comparison of native glass.")
        }
        _ = NSApplication.shared
        guard #available(macOS 26, *), let screen = NSScreen.main,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { throw XCTSkip("Requires visible glass.") }
        let frame = NSRect(x: floor(screen.visibleFrame.midX), y: floor(screen.visibleFrame.midY), width: 240, height: 36)
        let local = NSRect(origin: .zero, size: frame.size)
        let board = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        board.level = .floating
        board.hasShadow = false
        let scene = NSView(frame: local)
        scene.wantsLayer = true
        scene.layer?.backgroundColor = NSColor.white.cgColor
        for (i, color) in [NSColor.black, .systemBlue, .systemTeal, .systemYellow, .white, .systemPink].enumerated() {
            let band = CALayer()
            band.frame = CGRect(x: i * 38 + 6, y: i % 2 * 9, width: 28, height: 36)
            band.backgroundColor = color.cgColor
            scene.layer?.addSublayer(band)
        }
        board.contentView = scene
        let owner = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        owner.isOpaque = false
        owner.backgroundColor = .clear
        owner.level = .popUpMenu
        owner.hidesOnDeactivate = false
        let settings = NSWindow(contentRect: frame.offsetBy(dx: 0, dy: -95), styleMask: [.titled], backing: .buffered, defer: false)
        let quiet = try XCTUnwrap(ShelfAppearancePreset.builtIns.first { $0.id == "quiet-glass" }).appearance
        var reference = quiet
        reference.material = .appleGlass
        let shelf = ShelfBackdrop(frame: local, configuration: reference, content: NSView())
        owner.contentView = shelf
        let previous = NSWorkspace.shared.frontmostApplication
        defer {
            owner.orderOut(nil)
            settings.orderOut(nil)
            board.orderOut(nil)
            if NSApp.isActive, let previous, previous.processIdentifier != getpid() { previous.activate() }
        }
        func sample() async throws -> [UInt8] {
            try await Task.sleep(for: .milliseconds(350))
            let available = try await SCShareableContent.currentProcess
            let displayID = (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value
            let display = try XCTUnwrap(available.displays.first { $0.displayID == displayID })
            let ids = ([board, owner] + (owner.childWindows ?? [])).map(\.windowNumber)
            let windows = available.windows.filter { ids.contains(Int($0.windowID)) }
            XCTAssertEqual(windows.count, ids.count)
            let config = SCStreamConfiguration()
            config.sourceRect = NSRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                                       width: frame.width, height: frame.height)
            config.width = Int(frame.width)
            config.height = Int(frame.height)
            config.showsCursor = false
            config.ignoreShadowsDisplay = true
            config.includeChildWindows = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: windows),
                                                                   configuration: config)
            var rgba = [UInt8](repeating: 0, count: config.width * config.height * 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let ctx = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: config.width, height: config.height,
                                                  bitsPerComponent: 8, bytesPerRow: config.width * 4,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                ctx.draw(image, in: local)
            }
            return rgba
        }
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
            let sum = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            return Double(sum) / Double(Int(frame.width * frame.height) * 3)
        }

        board.orderFrontRegardless()
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        owner.makeKeyAndOrderFront(nil)
        let active = try await sample()
        XCTAssertTrue(owner.isKeyWindow)
        settings.makeKeyAndOrderFront(nil)
        let inactive = try await sample()
        XCTAssertFalse(owner.isKeyWindow)
        shelf.apply(quiet)
        owner.makeKeyAndOrderFront(nil)
        shelf.layoutSubtreeIfNeeded()
        let unlocked = try await sample()
        XCTAssertTrue(owner.isKeyWindow)
        for point in [NSPoint(x: 12, y: 18), NSPoint(x: 60, y: 10), NSPoint(x: 225, y: 18)] {
            let hit = NSWindow.windowNumber(at: owner.convertPoint(toScreen: point), belowWindowWithWindowNumber: 0)
            XCTAssertEqual(hit, owner.windowNumber, "Transparent padding must still belong to the interactive shelf.")
        }
        XCTAssertGreaterThan(difference(active, inactive), 3, "The scene must distinguish native active and inactive glass.")
        XCTAssertLessThan(difference(unlocked, inactive), 0.75, "Compare the colors transmitted by the entire shelf and rim.")
    }
}

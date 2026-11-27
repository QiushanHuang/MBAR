import AppKit
import MBARCore
import ScreenCaptureKit
import SwiftUI
import XCTest
@testable import MBAR

final class ShelfForegroundTests: XCTestCase {
    /// Exercise the actual window compositor. The filter includes only the three
    /// synthetic test windows and the two samples are never written to disk.
    @MainActor func testAdaptiveInkTracksTheBackgroundWithoutPaintingIconTiles() async throws {
        guard ProcessInfo.processInfo.environment["MBAR_TEST_GLASS_INK"] == "1" else {
            throw XCTSkip("Opt-in WindowServer foreground test.")
        }
        guard #available(macOS 26, *), CGPreflightScreenCaptureAccess(),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Requires native glass, existing capture access and transparency.")
        }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = CGRect(x: floor(screen.visibleFrame.midX) - 150, y: floor(screen.visibleFrame.midY), width: 300, height: 86)
        let board = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let backdrop = Background(frame: CGRect(origin: .zero, size: frame.size))
        board.hasShadow = false
        board.animationBehavior = .none
        board.contentView = backdrop
        board.level = .floating
        board.orderFrontRegardless()
        let icon = NSImage(size: CGSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setFill()
            CGRect(x: 3, y: 4, width: 14, height: 12).fill()
            NSGraphicsContext.current?.cgContext.clear(CGRect(x: 8, y: 4, width: 2, height: 12))
            return true
        }
        icon.isTemplate = true
        func row(reference: Bool, swapped: Bool) -> some View {
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 6) {
                        if reference {
                            Image(nsImage: icon).renderingMode(.template).resizable()
                                .interpolation(.high).scaledToFit().frame(width: 20, height: 20)
                                .foregroundStyle(((index == 0) != swapped || index == 2) ? Color.black : Color.white)
                        } else {
                            ShelfGlyph(image: icon, onClearGlass: true).frame(width: 20, height: 20)
                        }
                        if reference {
                            Text("状态").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(swapped && index == 0 ? Color.white : Color.black)
                        } else {
                            Text("状态").font(.system(size: 14, weight: .medium))
                                .shelfInk(clearGlass: true, treatment: .automatic)
                        }
                    }.padding(.leading, 12).frame(width: 100, height: 38, alignment: .leading)
                }
            }.shelfInkSurface(clearGlass: !reference, treatment: .automatic)
        }
        let host = NSHostingView(rootView: row(reference: false, swapped: false))
        let upper = CGRect(x: frame.minX, y: frame.maxY - 38, width: 300, height: 38)
        let shelf = ShelfPanel(contentRect: upper, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        shelf.animationBehavior = .none
        shelf.isOpaque = false
        shelf.backgroundColor = .clear
        shelf.level = .popUpMenu
        var appearance = try XCTUnwrap(ShelfAppearancePreset.builtIns.first { $0.id == "apple-glass" }).appearance
        appearance.frostAmount = 0
        shelf.contentView = ShelfBackdrop(frame: CGRect(origin: .zero, size: upper.size), configuration: appearance, content: host)
        shelf.orderFrontRegardless()
        let referenceHost = NSHostingView(rootView: row(reference: true, swapped: false))
        let reference = NSPanel(contentRect: upper.offsetBy(dx: 0, dy: -48), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        reference.contentView = referenceHost
        reference.level = .popUpMenu
        reference.backgroundColor = .clear
        reference.isOpaque = false
        reference.hasShadow = false
        reference.orderFrontRegardless()
        defer { reference.orderOut(nil); shelf.orderOut(nil); board.orderOut(nil) }

        // In the last two cases a sharp boundary runs through both solid
        // strokes of one icon and through the middle of one app label.
        for (swapped, split) in [(false, false), (true, false), (false, true), (true, true)] {
            backdrop.split = split
            referenceHost.rootView = row(reference: true, swapped: swapped)
            backdrop.swapped = swapped
            backdrop.needsDisplay = true
            try await Task.sleep(for: .milliseconds(500))
            let windows = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let number = try XCTUnwrap(screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)
            let display = try XCTUnwrap(windows.displays.first { $0.displayID == number.uint32Value })
            let own = windows.windows.filter { [board.windowNumber, shelf.windowNumber, reference.windowNumber].contains(Int($0.windowID)) }
            guard own.count == 3 else { return XCTFail("All test windows must be visible.") }
            let filter = SCContentFilter(display: display, including: own)
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                                       width: frame.width, height: frame.height)
            config.width = 300
            config.height = Int(frame.height)
            config.showsCursor = false
            config.ignoreShadowsDisplay = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bitmap = NSBitmapImageRep(cgImage: image)
            func pixel(_ x: Int, _ y: Int = 19) -> NSColor {
                bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            }
            for index in 0..<3 {
                let start = index * 100
                let bright = (index == 0) != swapped || index == 2
                let solid = pixel(start + 17)
                let gap = pixel(start + 20)
                let exterior = pixel(start + 34)
                let corner = pixel(start + 13)
                if split && index == 0 {
                    let firstStroke = solid.redComponent
                    let secondStroke = pixel(start + 26).redComponent
                    XCTAssertLessThan(abs(firstStroke - secondStroke), 0.08,
                                      "One icon must keep one ink across the light/dark boundary.")
                    XCTAssertTrue(firstStroke < 0.2 || firstStroke > 0.8)
                    // Use the reference drawing to locate actual solid text strokes:
                    // this is independent of font rasterization on the current Mac.
                    var tones = [CGFloat]()
                    for y in 11..<27 {
                        for x in 38..<68 {
                            let ref = pixel(x, y + 48)
                            if swapped ? ref.redComponent > 0.98 : ref.redComponent < 0.02 { tones.append(pixel(x, y).redComponent) }
                        }
                    }
                    XCTAssertGreaterThan(tones.count, 10)
                    if let high = tones.max(), let low = tones.min() {
                        XCTAssertLessThan(high - low, 0.12, "One label must keep one ink.")
                    }
                    continue
                }
                if bright { XCTAssertLessThan(solid.redComponent, 0.2) }
                else { XCTAssertGreaterThan(solid.redComponent, 0.8) }
                XCTAssertEqual(solid.redComponent, solid.greenComponent, accuracy: 0.04)
                XCTAssertEqual(solid.greenComponent, solid.blueComponent, accuracy: 0.04)
                // Compare the small cutout to the same template drawn directly in
                // the reference row at the same scale and pixel phase.
                let referenceGap = pixel(start + 20, 67)
                XCTAssertEqual(gap.redComponent, referenceGap.redComponent, accuracy: 0.04)
                XCTAssertEqual(gap.greenComponent, referenceGap.greenComponent, accuracy: 0.04)
                XCTAssertEqual(gap.blueComponent, referenceGap.blueComponent, accuracy: 0.04)
                XCTAssertEqual(corner.redComponent, exterior.redComponent, accuracy: 0.04)
                XCTAssertEqual(corner.greenComponent, exterior.greenComponent, accuracy: 0.04)
                XCTAssertEqual(corner.blueComponent, exterior.blueComponent, accuracy: 0.04)
                var readableStrokes = 0
                for y in 11..<27 {
                    for x in 38..<68 {
                        let p = pixel(start + x, y)
                        if bright ? max(p.redComponent, p.greenComponent, p.blueComponent) < 0.2
                                  : min(p.redComponent, p.greenComponent, p.blueComponent) > 0.8 {
                            readableStrokes += 1
                        }
                    }
                }
                XCTAssertGreaterThan(readableStrokes, 12, "The app label should have readable strokes on every field.")
            }
        }
    }

    private final class Background: NSView {
        var swapped = false
        var split = false
        override func draw(_ dirtyRect: NSRect) {
            let fields: [NSColor] = [swapped ? .black : .white, swapped ? .white : .black,
                                      NSColor(srgbRed: 0.18, green: 0.83, blue: 0.42, alpha: 1)]
            for (i, color) in fields.enumerated() {
                color.setFill()
                CGRect(x: CGFloat(i) * 100, y: 0, width: 100, height: bounds.height).fill()
            }
            if split {
                (swapped ? NSColor.white : NSColor.black).setFill()
                CGRect(x: 23, y: 48, width: 30, height: 38).fill()
            }
        }
    }
}

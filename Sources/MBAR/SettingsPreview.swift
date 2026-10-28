#if DEBUG
import AppKit
import ApplicationServices
import MBARCore
import SwiftUI

/// Isolated UI fixtures: no system hiding, live menu discovery, or production icon store.
@MainActor enum SettingsPreview {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MBAR-SettingsPreview-" + UUID().uuidString)
        let runtime = HidingRuntime(available: { true }, create: { _, completion in
            completion(nil)
            return NSObject()
        }, release: { _ in })
        let model = AppModel(hiding: HidingService(runtime: runtime), iconLibrary: IconLibrary(directory: directory))
        let identifier = Bundle.main.bundleIdentifier ?? ""
        let noPermission = identifier.hasSuffix(".Permission")
        let activeWithoutSelection = identifier.hasSuffix(".ActiveEmpty")
        let showShelf = identifier.hasSuffix(".Shelf")
        model.trusted = !noPermission
        model.hideRequested = activeWithoutSelection
        model.policy = activeWithoutSelection ? ShelfPolicy() : ShelfPolicy(assignments: [
            "preview.focus": .automatic, "preview.sync": .always, "preview.music": .automatic
        ])
        let examples = [("preview.focus", "专注模式"), ("preview.sync", "文件同步"),
                        ("preview.music", "音乐"), ("preview.calendar", "日历"),
                        ("preview.weather", "天气"), ("preview.notes", "备忘录")]
        if !noPermission {
            model.items = examples.map { bundle, name in
                MenuItem(id: bundle + "#0", bundle: bundle, name: name, title: name,
                         pid: 0, element: AXUIElementCreateApplication(getpid()), frame: nil)
            }
            model.items.append(MenuItem(id: "preview.sync#1", bundle: "preview.sync", name: "文件同步", title: "文件同步",
                                        pid: 0, element: AXUIElementCreateApplication(getpid()), frame: nil))
        } else {
            model.error = "需要辅助功能权限才能读取和打开菜单栏项目。"
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: showShelf ? 180 : 620, height: showShelf ? 36 : 660),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = showShelf ? "MBAR 下拉栏 · 开发预览" : "MBAR 设置 · 开发预览"
        window.isReleasedWhenClosed = false
        if identifier.hasSuffix(".Dark") { window.appearance = NSAppearance(named: .darkAqua) }
        if showShelf {
            model.previews["preview.focus#0"] = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: nil)
            let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 180, height: 36))
            effect.material = .popover
            effect.blendingMode = .behindWindow
            let host = NSHostingView(rootView: ShelfView(model: model, width: 180))
            host.frame = effect.bounds
            effect.addSubview(host)
            window.contentView = effect
        } else {
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        if showShelf, let host = window.contentView?.subviews.first {
            window.recalculateKeyViewLoop()
            window.makeFirstResponder(host)
        }
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime((window, model)) { app.run() }
    }
}
#endif

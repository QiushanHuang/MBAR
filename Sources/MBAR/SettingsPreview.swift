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
        let defaults = UserDefaults(suiteName: directory.lastPathComponent)!
        defer { defaults.removePersistentDomain(forName: directory.lastPathComponent) }
        let model = AppModel(hiding: HidingService(runtime: runtime), iconLibrary: IconLibrary(directory: directory), defaults: defaults)
        let identifier = Bundle.main.bundleIdentifier ?? ""
        let noPermission = identifier.hasSuffix(".Permission")
        let activeWithoutSelection = identifier.hasSuffix(".ActiveEmpty")
        let previewStyle = CommandLine.arguments.compactMap { argument -> ShelfStyle? in
            guard argument.hasPrefix("--shelf-preview=") else { return nil }
            return ShelfStyle(rawValue: String(argument.dropFirst("--shelf-preview=".count)))
        }.first
        let showShelf = identifier.hasSuffix(".Shelf") || previewStyle != nil
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
        if showShelf {
            model.shelfStyle = previewStyle ?? .strip
            if let choice = CommandLine.arguments.first(where: { $0.hasPrefix("--appearance-preset=") }) {
                model.selectShelfPreset(String(choice.dropFirst("--appearance-preset=".count)))
            }
            let symbols = ["moon.stars.fill", "arrow.triangle.2.circlepath", "music.note", "calendar", "cloud.sun", "note.text"]
            model.items = Array(model.items.prefix(examples.count))
            model.policy = ShelfPolicy(assignments: Dictionary(uniqueKeysWithValues: examples.map { ($0.0, .automatic) }))
            for (item, symbol) in zip(model.items, symbols) {
                model.previews[item.id] = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
        }
        let size = showShelf ? ShelfMetrics.size(style: model.shelfStyle, itemWidths: model.collected.map(model.previewWidth),
                                                  available: CGSize(width: 550, height: 400), showsLock: true)
                             : CGSize(width: 620, height: 660)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: showShelf ? [.borderless] : [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = showShelf ? "MBAR 下拉栏 · 开发预览" : "MBAR 设置 · 开发预览"
        window.isReleasedWhenClosed = false
        if identifier.hasSuffix(".Dark") { window.appearance = NSAppearance(named: .darkAqua) }
        if showShelf {
            window.backgroundColor = .clear
            window.isOpaque = false
            let host = ShelfHostingView(rootView: ShelfView(model: model, width: size.width, height: size.height))
            window.contentView = ShelfBackdrop(frame: NSRect(origin: .zero, size: size),
                                               configuration: model.shelfAppearance, content: host)
        } else {
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        if showShelf, let host = (window.contentView as? ShelfBackdrop)?.content {
            window.recalculateKeyViewLoop()
            window.makeFirstResponder(host)
        }
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime((window, model)) { app.run() }
    }
}
#endif

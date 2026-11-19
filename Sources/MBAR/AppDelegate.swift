import AppKit
import SwiftUI
import MBARCore
import Combine

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var settings: NSWindow?
    private let liveIcons = ShelfLiveIcons()
    private var shelf: ShelfPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var shelfAnchor: CGRect?
    private var shelfScreen: NSScreen?
    private var entryClickFrame: CGRect?
    private var invokingEntryClick: CGPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "MBAR")
            button.toolTip = "MBAR · 点击展开，右键设置"
            button.setAccessibilityLabel("MBAR 下拉栏")
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.showSettings = { [weak self] in self?.showSettings() }
        model.closeShelf = { [weak self] in self?.closeShelf(reason: .item) }
        model.onRecovery = { [weak self] in self?.closeShelf(reason: .recovery) }
        model.shelfVisible = { [weak self] in self?.shelf?.isVisible == true }
        model.onShelfContentChanged = { [weak self] in self?.resizeShelf() }
        model.onShelfAppearanceChanged = { [weak self] in
            guard let self, let backdrop = self.shelf?.contentView as? ShelfBackdrop else { return }
            backdrop.apply(self.model.shelfAppearance)
        }
        model.onShelfLiveIconsChanged = { [weak self] in
            guard let self, self.shelf?.isVisible == true, let display = self.model.preferredDisplay else { return }
            self.liveIcons.start(model: self.model, display: display)
            self.resizeShelf()
        }
        model.onPreparationCancelled = { [weak self] in
            guard let self, self.shelf == nil else { return }
            self.statusItem.button?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "MBAR")
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let shelf = self.shelf, shelf.isVisible else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.closeShelf(reason: .escape); return nil }
            if event.type != .keyDown, event.window != shelf, event.window != self.statusItem.button?.window,
               !ShelfDismissal.isEntryClick(NSEvent.mouseLocation, anchor: self.entryClickFrame) { self.closeShelf() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !ShelfDismissal.isEntryClick(NSEvent.mouseLocation, anchor: self.entryClickFrame) else { return }
            self.closeShelf()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.prepareForSystemSleep()
                self?.closeShelf(reason: .recovery)
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.resumeFromSystemSleep()
                self?.closeShelf(reason: .recovery)
            }
        })
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                       app.bundleIdentifier == "com.apple.MenuBarAgent" {
                        self?.model.suspendForSystemChange()
                    }
                    self?.closeShelf(reason: .applicationsChanged)
                    self?.model.refreshForApplicationChange()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.suspendForSystemChange(); self?.closeShelf(reason: .recovery) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.checkPermissions() } })
        model.suspendForSystemChange() // Login/startup can race MenuBarAgent's initial display surfaces too.
        showSettings()
        model.refresh { [weak self] in
            guard let self else { return }
            self.model.applyHiding()
            if let bundle = AppRelaunchRequest(arguments: CommandLine.arguments)?.iconBundle {
                self.model.configureIcon(bundle)
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.shelfRequested || shelf?.isVisible == true { return true }
        showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        liveIcons.stop(model: model)
        model.shutdown()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    @objc private func statusClicked() {
        let eventType = NSApp.currentEvent?.type
        if eventType == .leftMouseUp || eventType == .rightMouseUp { invokingEntryClick = NSEvent.mouseLocation }
        defer { invokingEntryClick = nil }
        if eventType == .rightMouseUp { showMenu() }
        else { toggleShelf() }
    }
    private func showMenu() {
        let menu = NSMenu()
        let locked = shelf?.isVisible == true && model.shelfLock.isLocked
        let toggleTitle = shelf?.isVisible == true ? "收起下拉栏" : "打开下拉栏"
        menu.addItem(withTitle: locked ? "下拉栏已锁定" : toggleTitle, action: locked ? nil : #selector(toggleShelf), keyEquivalent: "")
        let styles = menu.addItem(withTitle: "下拉栏样式", action: nil, keyEquivalent: "")
        styles.submenu = options(ShelfStyle.allCases.map { ($0.title, $0.rawValue) },
                                 selected: model.shelfStyle.rawValue, action: #selector(chooseStyle(_:)))
        let positions = menu.addItem(withTitle: "下拉栏位置", action: nil, keyEquivalent: "")
        positions.submenu = options([ShelfPlacement.left, .anchor, .right].map { ($0.title, $0.rawValue) },
                                    selected: model.shelfPlacement.rawValue, action: #selector(choosePlacement(_:)))
        if model.shelfPlacement == .anchor {
            let alignment = menu.addItem(withTitle: "入口下方展开方向", action: nil, keyEquivalent: "")
            alignment.submenu = options(ShelfAlignment.allCases.map { ($0.title, $0.rawValue) },
                                        selected: model.shelfAlignment.rawValue, action: #selector(chooseAlignment(_:)))
        }
        let presets = menu.addItem(withTitle: "下拉栏外观预设", action: nil, keyEquivalent: "")
        presets.submenu = options(model.shelfPresets.map { ($0.name, $0.id) },
                                  selected: model.selectedShelfPresetID, action: #selector(choosePreset(_:)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "显示全部图标", action: #selector(showAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "退出 MBAR", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    private func options(_ choices: [(String, String)], selected: String, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for (title, value) in choices {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.representedObject = value
            item.target = self
            item.state = value == selected ? .on : .off
        }
        return menu
    }
    @objc private func chooseStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let value = ShelfStyle(rawValue: raw) { model.shelfStyle = value }
    }
    @objc private func choosePlacement(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let value = ShelfPlacement(rawValue: raw) { model.shelfPlacement = value }
    }
    @objc private func chooseAlignment(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let value = ShelfAlignment(rawValue: raw) { model.shelfAlignment = value }
    }
    @objc private func choosePreset(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { model.selectShelfPreset(id) }
    }
    @objc func showAll() { model.restoreAll(); closeShelf(reason: .recovery) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showSettings() {
        closeShelf(reason: .settings)
        // Opening Settings does not expose always-hidden items. Show All is explicit.
        if shelf?.isVisible != true { model.endShelfSession() }
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MBAR 设置"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 580, height: 540)
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
        model.refresh()
    }
    @objc func toggleShelf() {
        if model.shelfRequested { model.cancelSnapshots(); model.applyHiding(); statusItem.button?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "MBAR"); return }
        if shelf?.isVisible == true { closeShelf(reason: .toggle); return }
        model.checkPermissions()
        guard model.trusted else {
            showSettings()
            model.error = "需要辅助功能权限以读取并打开菜单栏项目。原始图标资源不需要屏幕录制权限。"
            return
        }
        let click = invokingEntryClick
        let sourceScreen = (settings?.isKeyWindow == true ? settings?.screen : nil) ?? NSApp.currentEvent?.window?.screen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        settings?.orderOut(nil)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "正在读取图标")
        // Load original artwork without ever changing the native bar layout.
        model.prepareShelf { [weak self] in
            guard let self else { return }
            let rect = self.statusItem.button.flatMap { button in
                button.window?.convertToScreen(button.convert(button.bounds, to: nil))
            }
            // A hosted status item's AppKit window can be offscreen. Settings can
            // still open the shelf on its originating display in that case.
            let screens = NSScreen.screens
            let source = sourceScreen.flatMap { previous in screens.first { $0 == previous } }
            // Check the owning display. A placeholder at the bottom of one display
            // can coincide with the top menu-bar band of a vertically adjacent one.
            let entryScreen = self.statusItem.button?.window?.screen.flatMap { screen in
                rect.map { PanelLayout.isMenuBarAnchor($0, on: screen.frame) } == true ? screen : nil
            }
            let clickedScreen = click.flatMap { point in screens.first { $0.frame.contains(point) } }
            guard let screen = clickedScreen ?? source ?? entryScreen ?? NSScreen.main else { return }
            let clickedAnchor = click.flatMap {
                PanelLayout.clickedAnchor(point: $0, display: screen.frame, usable: screen.visibleFrame,
                                          menuBarHeight: NSStatusBar.system.thickness)
            }
            let validEntry: CGRect?
            if let rect, entryScreen == screen, click.map({ rect.insetBy(dx: -2, dy: -2).contains($0) }) ?? true {
                validEntry = rect
            } else {
                validEntry = clickedAnchor
            }
            let anchor = validEntry ?? PanelLayout.fallbackAnchor(display: screen.frame, usable: screen.visibleFrame,
                                                                  menuBarHeight: NSStatusBar.system.thickness)
            self.presentShelf(anchor: anchor, screen: screen, entry: validEntry)
        }
    }
    private func shelfFrame(anchor: CGRect, screen: NSScreen) -> CGRect {
        let bounds = screen.visibleFrame
        let size = ShelfMetrics.size(style: model.shelfStyle, itemWidths: model.collected.map(model.previewWidth),
                                     available: bounds.insetBy(dx: 8, dy: 8).size, showsLock: model.shelfLock.showsButton, scale: model.shelfIconScale, tallestGlyphHeight: model.shelfMaxGlyphHeight)
        return PanelLayout.frame(anchor: anchor, screen: bounds, requested: size,
                                 placement: model.shelfPlacement, alignment: model.shelfAlignment)
    }
    private func presentShelf(anchor: CGRect, screen: NSScreen, entry: CGRect?) {
        entryClickFrame = entry
        shelfAnchor = anchor; shelfScreen = screen
        let frame = shelfFrame(anchor: anchor, screen: screen)
        let panel = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .popUpMenu
        panel.animationBehavior = .none
        panel.onCancel = { [weak self] in self?.closeShelf(reason: .escape) }
        panel.hasShadow = true; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = ShelfHostingView(rootView: ShelfView(model: model, width: frame.width, height: frame.height))
        panel.contentView = ShelfBackdrop(frame: NSRect(origin: .zero, size: frame.size),
                                         configuration: model.shelfAppearance, content: host)
        shelf = panel
        panel.setFrame(frame, display: true)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let display = CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        model.preferredDisplay = display
        liveIcons.start(model: model, display: display)
        // Focus the host without selecting an item; the first Tab enters the shelf.
        panel.makeFirstResponder(host)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        statusItem.button?.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "收起 MBAR")
    }
    private func resizeShelf() {
        guard let panel = shelf, panel.isVisible, let anchor = shelfAnchor, let screen = shelfScreen else { return }
        let frame = shelfFrame(anchor: anchor, screen: screen)
        guard panel.frame != frame else { return }
        if let backdrop = panel.contentView as? ShelfBackdrop, let host = backdrop.content as? ShelfHostingView {
            host.rootView = ShelfView(model: model, width: frame.width, height: frame.height)
        }
        panel.setFrame(frame, display: true)
    }
    func closeShelf(reason: ShelfCloseReason = .outside) {
        guard model.shelfLock.shouldClose(for: reason) else { return }
        if reason == .recovery { model.unlockShelf() }
        let wasOpen = shelf != nil
        shelf?.orderOut(nil); shelf = nil
        liveIcons.stop(model: model)
        shelfAnchor = nil; shelfScreen = nil; entryClickFrame = nil
        if wasOpen || reason == .recovery { model.endShelfSession() }
        statusItem?.button?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "MBAR")
    }
}

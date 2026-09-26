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
    private var shelf: ShelfPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var shelfAnchor: CGRect?
    private var shelfScreen: NSScreen?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "MBAR")
            button.toolTip = "MBAR · 点击展开，右键设置"
            button.setAccessibilityLabel("MBAR")
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.showSettings = { [weak self] in self?.showSettings() }
        model.closeShelf = { [weak self] in self?.closeShelf(reason: .item) }
        model.onRecovery = { [weak self] in self?.closeShelf(reason: .recovery) }
        model.shelfVisible = { [weak self] in self?.shelf?.isVisible == true }
        model.onShelfContentChanged = { [weak self] in self?.resizeShelf() }
        model.onPreparationCancelled = { [weak self] in
            guard let self, self.shelf == nil else { return }
            self.statusItem.button?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "MBAR")
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let shelf = self.shelf, shelf.isVisible else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.closeShelf(reason: .escape); return nil }
            if event.type != .keyDown, event.window != shelf, event.window != self.statusItem.button?.window,
               !ShelfDismissal.isEntryClick(NSEvent.mouseLocation, anchor: self.shelfAnchor) { self.closeShelf() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !ShelfDismissal.isEntryClick(NSEvent.mouseLocation, anchor: self.shelfAnchor) else { return }
            self.closeShelf()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Refresh topology without dropping always-hidden protection.
                MainActor.assumeIsolated { self?.closeShelf(reason: .recovery); self?.model.suspendForSystemChange() }
            })
        }
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closeShelf(reason: .applicationsChanged)
                    self?.model.refreshForApplicationChange()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeShelf(reason: .recovery); self?.model.suspendForSystemChange() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.checkPermissions() } })
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
        model.shutdown()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else { toggleShelf() }
    }
    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开下拉栏", action: #selector(toggleShelf), keyEquivalent: "")
        menu.addItem(withTitle: "显示全部图标", action: #selector(showAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "退出 MBAR", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    @objc func showAll() { model.restoreAll(); closeShelf(reason: .recovery) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showSettings() {
        closeShelf(reason: .settings)
        // Opening Settings does not expose always-hidden items. Show All is explicit.
        if shelf?.isVisible != true { model.endShelfSession() }
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "MBAR 设置"
            window.isReleasedWhenClosed = false
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
        settings?.orderOut(nil)
        guard let button = statusItem.button, let window = button.window else { showSettings(); return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        // Quartz uses top-left origin relative to the primary display.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        model.preferredDisplay = CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        shelfAnchor = anchor; shelfScreen = screen
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "正在读取图标")
        // Load original artwork without ever changing the native bar layout.
        model.prepareShelf { [weak self] in
            guard let self, let button = self.statusItem.button, let window = button.window,
                  let currentScreen = window.screen else { return }
            // The original anchor predates native reflow and is now stale.
            let currentAnchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            self.presentShelf(anchor: currentAnchor, screen: currentScreen)
        }
    }
    private func presentShelf(anchor: CGRect, screen: NSScreen) {
        shelfAnchor = anchor; shelfScreen = screen
        let width = ShelfMetrics.width(itemWidths: model.collected.map { model.previewWidth(for: $0) }, available: screen.frame.width - 16, showsLock: model.shelfLock.showsButton)
        let frame = PanelLayout.frame(anchor: anchor, screen: screen.frame, requested: CGSize(width: width, height: ShelfMetrics.height))
        let panel = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .popUpMenu
        panel.animationBehavior = .none
        panel.onCancel = { [weak self] in self?.closeShelf(reason: .escape) }
        panel.hasShadow = true; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        effect.wantsLayer = true; effect.layer?.cornerRadius = 10; effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        let host = NSHostingView(rootView: ShelfView(model: model, width: frame.width))
        host.frame = effect.bounds; host.autoresizingMask = [.width, .height]
        effect.addSubview(host); panel.contentView = effect
        shelf = panel
        panel.setFrame(frame, display: true)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        // Opening the shelf is not selecting its first item. Tab navigation
        // remains available, with focus rings disabled on the icon controls.
        panel.makeFirstResponder(nil)
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
        let width = ShelfMetrics.width(itemWidths: model.collected.map { model.previewWidth(for: $0) }, available: screen.frame.width - 16, showsLock: model.shelfLock.showsButton)
        let frame = PanelLayout.frame(anchor: anchor, screen: screen.frame, requested: CGSize(width: width, height: ShelfMetrics.height))
        if let host = panel.contentView?.subviews.first as? NSHostingView<ShelfView> { host.rootView = ShelfView(model: model, width: frame.width) }
        panel.setFrame(frame, display: true)
    }
    func closeShelf(reason: ShelfCloseReason = .outside) {
        guard model.shelfLock.shouldClose(for: reason) else { return }
        if reason == .recovery { model.unlockShelf() }
        let wasOpen = shelf != nil
        shelf?.orderOut(nil); shelf = nil
        shelfAnchor = nil; shelfScreen = nil
        if wasOpen || reason == .recovery { model.endShelfSession() }
        statusItem?.button?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "MBAR")
    }
}

import AppKit
import SwiftUI
import ApplicationServices
import MBARCore

@MainActor final class AppModel: ObservableObject {
    @Published var items: [MenuItem] = []
    @Published var policy: ShelfPolicy
    @Published var trusted = AXIsProcessTrusted()
    @Published var captureGranted = CGPreflightScreenCaptureAccess()
    @Published var refreshing = false
    @Published var capturing = false
    private(set) var shelfRequested = false
    @Published var hideRequested = UserDefaults.standard.bool(forKey: "hidingEnabled")
    @Published var status = "为菜单栏应用选择显示方式"
    @Published var error: String?
    @Published var phase: VisibilityState.Phase = .visible
    @Published var previews: [String: NSImage] = [:]
    @Published var snapshotDate: Date?
    @Published var iconSources: [String: String] = [:]
    @Published private(set) var shelfLock = ShelfLockPolicy(
        showsButton: UserDefaults.standard.object(forKey: "showShelfLockButton") as? Bool ?? true)
    let discovery = MenuDiscovery()
    let hiding = HidingService()
    private let iconSource = MenuIconSource()
    private var refreshGeneration = 0
    private var refreshWaiters: [() -> Void] = []
    private var interactionGeneration = 0
    private var snapshotSession = SnapshotSession()
    private var snapshotTask: Task<Void, Never>?
    private var menuObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var menuContext: MenuContext?
    var preferredDisplay: CGRect?
    var showSettings: (() -> Void)?
    var closeShelf: (() -> Void)?
    var onRecovery: (() -> Void)?
    var shelfVisible: (() -> Bool)?
    var onShelfContentChanged: (() -> Void)?
    var onPreparationCancelled: (() -> Void)?
    var groups: [(bundle: String, items: [MenuItem])] {
        Dictionary(grouping: items, by: \.bundle).map { ($0.key, $0.value) }
            .sorted { ($0.items.first?.name ?? "").localizedStandardCompare($1.items.first?.name ?? "") == .orderedAscending }
    }
    var collected: [MenuItem] {
        items.filter { policy.automatic.contains($0.bundle) }
            .sorted { a, b in
                ShelfOrderKey(name: a.name, id: a.id) < ShelfOrderKey(name: b.name, id: b.id)
            }
    }
    var apiAvailable: Bool { hiding.available }
    var ownBundle: String { Bundle.main.bundleIdentifier ?? "local.qiushan.MBAR" }
    func toggleShelfLock() { shelfLock.toggle() }
    func unlockShelf() { shelfLock.unlock() }
    func setShowsShelfLock(_ value: Bool) {
        shelfLock.setShowsButton(value)
        UserDefaults.standard.set(value, forKey: "showShelfLockButton")
        onShelfContentChanged?()
    }
    init() {
        let saved = (UserDefaults.standard.dictionary(forKey: "itemCategories") as? [String: String] ?? [:]).compactMapValues(ItemCategory.init(rawValue:))
        let legacy = Set(UserDefaults.standard.stringArray(forKey: "selectedBundles") ?? [])
        policy = ShelfPolicy(assignments: saved, legacySelected: legacy)
        UserDefaults.standard.set(policy.assignments.mapValues(\.rawValue), forKey: "itemCategories")
        hiding.onChange = { [weak self] phase, message in
            guard let self else { return }
            self.phase = phase
            if let message {
                self.error = message
                if phase == .visible { self.hideRequested = false; UserDefaults.standard.set(false, forKey: "hidingEnabled") }
            }
        }
    }
    func setCategory(_ bundle: String, _ category: ItemCategory) {
        guard MenuPolicy.canHide(bundle, own: ownBundle) else { return }
        cancelSnapshots()
        policy.assignments[bundle] = category
        UserDefaults.standard.set(policy.assignments.mapValues(\.rawValue), forKey: "itemCategories")
        previews = previews.filter { key, _ in collected.contains { $0.id == key } }
        applyHiding()
        onShelfContentChanged?()
        if shelfVisible?() == true {
            updatePreviews { [weak self] in self?.onShelfContentChanged?() }
        }
    }
    func checkPermissions() {
        let previouslyTrusted = trusted
        trusted = AXIsProcessTrusted(); captureGranted = CGPreflightScreenCaptureAccess()
        if trusted && !previouslyTrusted { error = nil }
        if !trusted { restoreAll(); items = []; error = "需要辅助功能权限才能读取和打开菜单栏项目。" }
    }
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func requestCapture() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    private func finishRefreshWaiters() {
        let callbacks = refreshWaiters; refreshWaiters.removeAll()
        for callback in callbacks { callback() }
    }
    func refreshContents() {
        refresh { [weak self] in
            guard let self, self.shelfVisible?() == true else { return }
            self.updatePreviews { [weak self] in self?.onShelfContentChanged?() }
        }
    }
    func refresh(after: (() -> Void)? = nil) {
        if let after { refreshWaiters.append(after) }
        checkPermissions()
        guard trusted else { finishRefreshWaiters(); return }
        guard !refreshing else { return }
        refreshGeneration += 1; let generation = refreshGeneration
        refreshing = true
        discovery.scan { [weak self] snapshot in
            guard let self, self.refreshGeneration == generation else { return }
            self.refreshing = false
            if let error = snapshot.error { self.error = error }
            else {
                self.items = snapshot.items
                let valid = Set(snapshot.items.map(\.id))
                self.previews = self.previews.filter { valid.contains($0.key) }
                self.status = self.items.isEmpty ? "没有发现可读取的菜单栏图标" : "已发现 \(self.groups.count) 个应用"
            }
            self.onShelfContentChanged?()
            self.finishRefreshWaiters()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.refreshGeneration == generation, self.refreshing else { return }
            self.refreshGeneration += 1; self.refreshing = false
            self.restoreAll(); self.error = "读取菜单栏超时，请关闭无响应的应用再刷新。"
            self.finishRefreshWaiters()
        }
    }
    func enableHiding(_ enabled: Bool) {
        error = nil
        guard enabled else { restoreAll(); return }
        checkPermissions()
        guard trusted, !policy.hidden.isEmpty else { error = "请授权辅助功能，并为至少一个应用选择隐藏方式。"; return }
        hideRequested = true
        UserDefaults.standard.set(true, forKey: "hidingEnabled")
        applyHiding()
    }
    func applyHiding(revealing: Set<String> = []) {
        guard hideRequested, AXIsProcessTrusted() else { hiding.restore(); return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let hidden = policy.hidden.intersection(running).subtracting(revealing)
        hiding.hide(running: running, selected: hidden, own: ownBundle)
    }
    func restoreAll() {
        cancelSnapshots()
        interactionGeneration += 1; stopMenuObserver()
        hideRequested = false
        UserDefaults.standard.set(false, forKey: "hidingEnabled")
        hiding.restore()
        status = "已暂停收纳，全部图标恢复显示"
        shelfLock.unlock()
        onRecovery?()
    }
    func shutdown() {
        cancelSnapshots(); interactionGeneration += 1; stopMenuObserver()
        hiding.restore() // Preserve the user's enabled preference across normal restart.
    }
    func suspendForSystemChange() {
        if shelfRequested { return } // Finish the bounded capture, then reapply the current running-app policy.
        cancelSnapshots(); interactionGeneration += 1; stopMenuObserver()
        previews.removeAll()
        applyHiding()
        // Keep always-hidden protection active while refreshing topology.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh { self?.applyHiding() } }
    }
    func refreshForApplicationChange() {
        if let element = observedElement {
            var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
            if NSRunningApplication(processIdentifier: pid)?.isTerminated != false {
                interactionGeneration += 1; stopMenuObserver()
            }
        }
        refresh { [weak self] in
            guard let self else { return }
            if self.menuObserver == nil { self.applyHiding() }
            if self.shelfVisible?() == true {
                self.updatePreviews { [weak self] in self?.onShelfContentChanged?() }
            }
        }
    }
    func cancelSnapshots(clearRequest: Bool = true) {
        snapshotSession.cancel()
        snapshotTask?.cancel()
        snapshotTask = nil; capturing = false
        if clearRequest { shelfRequested = false; onPreparationCancelled?() }
    }
    func endShelfSession() {
        cancelSnapshots()
        if menuObserver == nil { applyHiding() }
    }
    func prepareShelf(completion: @escaping () -> Void) {
        interactionGeneration += 1; stopMenuObserver(); cancelSnapshots()
        shelfRequested = true
        error = nil
        refresh { [weak self] in
            guard let self, self.shelfRequested else { return }
            self.updatePreviews(completion: completion)
        }
    }
    func updatePreviews(completion: @escaping () -> Void) {
        checkPermissions()
        guard (shelfRequested || shelfVisible?() == true), trusted else { return }
        cancelSnapshots(clearRequest: false)
        let inputs = collected
        let token = snapshotSession.begin()
        capturing = true
        // Deliberately no visibility assertion, overflow action, or screen crop.
        // Both hidden sections remain concealed throughout icon loading.
        snapshotTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await self.iconSource.load(inputs)
            guard self.snapshotSession.accepts(token), !Task.isCancelled,
                  self.shelfRequested || self.shelfVisible?() == true else { return }
            self.previews = loaded.images
            self.iconSources = loaded.sources
            self.snapshotDate = Date()
            UserDefaults.standard.set([
                "requested": inputs.map(\.id), "loaded": loaded.images.keys.sorted(),
                "sources": loaded.sources, "failures": loaded.failures, "timestamp": ISO8601DateFormatter().string(from: Date())
            ], forKey: "lastIconSourceDiagnostics")
            let missing = inputs.filter { loaded.images[$0.id] == nil }
            self.error = missing.isEmpty ? nil : "图标未就绪：" + missing.map {
                "\($0.name)（\(loaded.failures[$0.id] ?? "图像读取失败")）"
            }.joined(separator: "、")
            self.status = "已读取 \(loaded.images.count) 个完整菜单图标"
            self.capturing = false; self.shelfRequested = false
            self.snapshotSession.cancel(); self.snapshotTask = nil
            completion()
        }
    }
    // Application icons are used only to identify apps in Settings, never in the shelf.
    func settingsIcon(for item: MenuItem) -> NSImage {
        NSRunningApplication(processIdentifier: item.pid)?.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: item.name)!
    }
    func previewWidth(for item: MenuItem) -> CGFloat { ShelfMetrics.itemWidth(previews[item.id]?.size ?? item.frame?.size) }
    func openItem(_ item: MenuItem, right: Bool, fromSettings: Bool = false) {
        guard fromSettings || policy.category(item.bundle) == .automatic else { return }
        cancelSnapshots(); closeShelf?()
        error = nil
        interactionGeneration += 1; let generation = interactionGeneration
        stopMenuObserver()
        // Only the explicitly clicked app is temporarily exempted. Other
        // always-hidden items never become visible during this menu operation.
        applyHiding(revealing: [item.bundle])
        status = "正在打开 \(item.name)"
        observeMenu(of: item, generation: generation)
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<80 {
                guard generation == self.interactionGeneration else { return }
                if self.phase != .activating { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard generation == self.interactionGeneration else { return }
            self.discovery.press(item, right: right, preferredDisplay: self.preferredDisplay) { [weak self] success, message in
                guard let self, generation == self.interactionGeneration else { return }
                if let message { self.error = message; self.status = message; self.showSettings?() }
                else { self.status = "菜单关闭后恢复隐藏；自定义弹窗可再点 MBAR 收起" }
            }
        }
    }
    private final class MenuContext {
        weak var model: AppModel?
        let generation: Int
        var lifetime = MenuLifetime()
        init(model: AppModel, generation: Int) { self.model = model; self.generation = generation }
    }
    private func observeMenu(of item: MenuItem, generation: Int) {
        let root = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, context in
            guard let context else { return }
            let session = Unmanaged<MenuContext>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                guard let model = session.model, session.generation == model.interactionGeneration else { return }
                if notification as String == kAXMenuOpenedNotification { session.lifetime.opened() }
                else if session.lifetime.closed() { model.menuClosed(generation: session.generation) }
            }
        }
        guard AXObserverCreate(item.pid, callback, &observer) == .success, let observer else { return }
        let context = MenuContext(model: self, generation: generation)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        guard AXObserverAddNotification(observer, root, kAXMenuOpenedNotification as CFString, pointer) == .success else { return }
        guard AXObserverAddNotification(observer, root, kAXMenuClosedNotification as CFString, pointer) == .success else {
            AXObserverRemoveNotification(observer, root, kAXMenuOpenedNotification as CFString); return
        }
        menuContext = context; menuObserver = observer; observedElement = root
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    private func menuClosed(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, generation == self.interactionGeneration, self.menuContext?.lifetime.depth == 0 else { return }
            self.stopMenuObserver()
            if self.hideRequested { self.applyHiding() }
        }
    }
    private func stopMenuObserver() {
        if let observer = menuObserver {
            if let element = observedElement {
                AXObserverRemoveNotification(observer, element, kAXMenuOpenedNotification as CFString)
                AXObserverRemoveNotification(observer, element, kAXMenuClosedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        menuObserver = nil; observedElement = nil; menuContext = nil
    }
}

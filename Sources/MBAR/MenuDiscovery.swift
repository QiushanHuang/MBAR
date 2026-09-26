import AppKit
import ApplicationServices
import MBARCore

struct MenuItem {
    let id: String
    let bundle: String
    let name: String
    let title: String
    let pid: pid_t
    let element: AXUIElement
    var frame: CGRect? // Quartz coordinates, refreshed before using.
}
struct MenuSnapshot {
    var items: [MenuItem]
    var error: String?
}
struct CaptureLayout {
    var items: [MenuItem]
    var overflow: UUID?
    var display: CGRect?
}
private final class CaptureCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

// All cross-process AX calls run on this serial background queue, never the UI thread.
// The only mutable member (overflowLease) is accessed exclusively on queue.
final class MenuDiscovery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.qiushan.MBAR.accessibility", qos: .userInitiated)
    private var overflowLease = OverflowLease() // Confined to queue.
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    static func role(_ element: AXUIElement) -> String {
        attribute(element, kAXRoleAttribute) as? String ?? ""
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        if let value = attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() {
            var rect = CGRect.zero
            if AXValueGetValue(value as! AXValue, .cgRect, &rect) { return rect }
        }
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    private static func extras(_ root: AXUIElement) -> [AXUIElement] {
        if let bar = attribute(root, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            return children(bar as! AXUIElement)
        }
        return [] // Never confuse an application's File/Edit menu with status items.
    }
    func scan(completion: @escaping (MenuSnapshot) -> Void) {
        queue.async {
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { completion(MenuSnapshot(items: [], error: "请先在系统设置中允许 MBAR 使用辅助功能。")) }; return
            }
            let apps = NSWorkspace.shared.runningApplications
            var items: [MenuItem] = []
            var frames: [pid_t: [CGRect]] = [:]
            // macOS 27 hosts status items in MenuBarAgent. Its groups supply actual on-screen geometry.
            if let agent = apps.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) {
                let root = AXUIElementCreateApplication(agent.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.2)
                for window in Self.children(root) where Self.role(window) == kAXWindowRole {
                    for group in Self.children(window) {
                        guard let rect = Self.frame(group), rect.width > 0, rect.height > 0 else { continue }
                        for child in Self.children(group) {
                            var pid: pid_t = 0; AXUIElementGetPid(child, &pid)
                            if pid != agent.processIdentifier && pid > 0 { frames[pid, default: []].append(rect) }
                        }
                    }
                }
            }
            for app in apps {
                guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                      !bundle.hasPrefix("com.apple.") else { continue }
                let root = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.15)
                let leaves = Self.extras(root)
                for (index, leaf) in leaves.enumerated() {
                    AXUIElementSetMessagingTimeout(leaf, 0.2)
                    let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute].compactMap {
                        Self.attribute(leaf, $0) as? String
                    }.first(where: { !$0.isEmpty }) ?? app.localizedName ?? bundle
                    // One item can have one group per screen. Multiple-item apps are disambiguated by AX action, not guessed coordinates.
                    let frame = leaves.count == 1 ? frames[app.processIdentifier]?.first : nil
                    items.append(MenuItem(id: "\(bundle)#\(index)", bundle: bundle, name: app.localizedName ?? bundle,
                                          title: title, pid: app.processIdentifier, element: leaf, frame: frame))
                }
            }
            let result = MenuSnapshot(items: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, error: nil)
            DispatchQueue.main.async { completion(result) }
        }
    }
    /// Passive geometry only. Unlike captureFrames, this never invokes overflow or changes visibility.
    func visibleFrames(_ items: [MenuItem]) async -> [MenuItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                guard AXIsProcessTrusted() else { continuation.resume(returning: []); return }
                var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
                guard CGGetActiveDisplayList(16, &ids, &count) == .success else { continuation.resume(returning: []); return }
                let displays = ids.prefix(Int(count)).sorted { $0 == CGMainDisplayID() && $1 != CGMainDisplayID() }.map { CGDisplayBounds($0) }
                // Confirm the app still exposes exactly one item; PID alone cannot disambiguate multiple buttons.
                let eligible = items.filter {
                    let root = AXUIElementCreateApplication($0.pid); AXUIElementSetMessagingTimeout(root, 0.15)
                    return Self.extras(root).count == 1
                }
                var results: [MenuItem] = []
                for display in displays {
                    let positions = Self.hostedFrames(eligible, display: display)
                    for item in eligible where !results.contains(where: { $0.id == item.id }) {
                        guard let frame = positions[item.id] else { continue }
                        var copy = item; copy.frame = frame; results.append(copy)
                    }
                }
                continuation.resume(returning: results)
            }
        }
    }
    /// Reveals only the system overflow needed for already-allowed items.
    /// The app's visibility assertion decides which bundles may be shown.
    func captureFrames(_ items: [MenuItem], preferredDisplay: CGRect?) async -> CaptureLayout {
        let cancellation = CaptureCancellation()
        return await withTaskCancellationHandler(operation: {
          await withCheckedContinuation { continuation in
            queue.async {
                var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
                var count: UInt32 = 0
                CGGetActiveDisplayList(16, &displayIDs, &count)
                var displays = displayIDs.prefix(Int(count)).map { CGDisplayBounds($0) }
                if let preferredDisplay {
                    displays.sort { a, b in a == preferredDisplay && b != preferredDisplay }
                }
                let grouped = Dictionary(grouping: items, by: \.pid)
                let singleItems = items.filter { grouped[$0.pid]?.count == 1 }
                let deadline = Date().addingTimeInterval(2.5)
                var found: [String: CGRect] = [:]
                var triedOverflow = false
                var lease: UUID?
                let targetDisplay = preferredDisplay ?? displays.first
                repeat {
                    if cancellation.cancelled { break }
                    var pass: [String: CGRect] = [:]
                    for display in displays { pass.merge(Self.hostedFrames(singleItems, display: display)) { old, _ in old } }
                    let allStable = pass.count == singleItems.count && pass.allSatisfy { found[$0.key] == $0.value }
                    found = pass
                    if allStable { break }
                    if !triedOverflow, let display = targetDisplay {
                        triedOverflow = Self.revealOverflow(display: display) // Missing button during reflow is not a completed attempt.
                        if triedOverflow { lease = self.overflowLease.claim() }
                    }
                    Thread.sleep(forTimeInterval: 0.08)
                } while Date() < deadline
                Thread.sleep(forTimeInterval: 0.08)
                var current: [String: CGRect] = [:]
                for display in displays { current.merge(Self.hostedFrames(singleItems, display: display)) { old, _ in old } }
                let stable: [MenuItem] = singleItems.compactMap { item in
                    guard let first = found[item.id], let latest = current[item.id],
                          let display = displays.first(where: { $0.contains(latest) }),
                          ClickGeometry.point(first: first, current: latest, screen: display) != nil else { return nil }
                    var copy = item; copy.frame = latest; return copy
                }
                continuation.resume(returning: CaptureLayout(items: cancellation.cancelled ? [] : stable, overflow: lease, display: targetDisplay))
            }
          }
        }, onCancel: { cancellation.cancel() })
    }
    /// Always called, including after cancellation. An older capture cannot
    /// collapse an overflow that a newer capture has taken ownership of.
    func restoreOverflow(_ layout: CaptureLayout) async {
        guard let token = layout.overflow, let display = layout.display else { return }
        await withCheckedContinuation { continuation in
            queue.async {
                if self.overflowLease.consume(token) { _ = Self.setOverflow(expanded: false, display: display) }
                continuation.resume()
            }
        }
    }
    func validateCaptureFrames(_ items: [MenuItem]) async -> [MenuItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
                var count: UInt32 = 0
                CGGetActiveDisplayList(16, &displayIDs, &count)
                let displays = displayIDs.prefix(Int(count)).map { CGDisplayBounds($0) }
                var verified: [MenuItem] = []
                for display in displays {
                    let current = Self.hostedFrames(items, display: display)
                    for item in items where item.frame.map({ display.contains($0) }) == true {
                        guard ClickGeometry.point(first: item.frame, current: current[item.id], screen: display) != nil else { continue }
                        verified.append(item)
                    }
                }
                continuation.resume(returning: verified)
            }
        }
    }
    func waitForStableLayout(display: CGRect?) async -> Bool {
        var gate = NativeTransitionGate(startedAt: ProcessInfo.processInfo.systemUptime)
        let deadline = ProcessInfo.processInfo.systemUptime + 2.5
        while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            let signature: [String] = await withCheckedContinuation { continuation in
                queue.async {
                    let windows = Self.hostWindows()
                    let signature = windows.flatMap { window in
                        Self.children(window).compactMap { group -> String? in
                            guard let rect = Self.frame(group), rect.width > 0, rect.height > 0,
                                  display.map({ $0.contains(rect) }) ?? true else { return nil }
                            // Geometry only; live titles must not prevent a static capture.
                            return "\(rect.minX.rounded()),\(rect.minY.rounded()),\(rect.width.rounded()),\(rect.height.rounded())"
                        }
                    }.sorted()
                    continuation.resume(returning: signature)
                }
            }
            if gate.observe(signature, at: ProcessInfo.processInfo.systemUptime) { return true }
            do { try await Task.sleep(nanoseconds: 60_000_000) } catch { return false }
        }
        return false
    }
    func press(_ item: MenuItem, right: Bool, preferredDisplay: CGRect?, completion: @escaping (Bool, String?) -> Void) {
        queue.async {
            // macOS 27 may report AXPress success for an off-screen status item
            // without opening its menu. Prefer a fresh, verified host position.
            if let display = preferredDisplay, Self.clickHostedItem(item, right: right, display: display) {
                NSLog("MBAR native click sent %@", item.bundle)
                DispatchQueue.main.async { completion(true, nil) }; return
            }
            var actions: CFArray?
            AXUIElementCopyActionNames(item.element, &actions)
            let available = actions as? [String] ?? []
            let action = right ? kAXShowMenuAction : kAXPressAction
            NSLog("MBAR action %@ available=%@ requested=%@", item.bundle, available.joined(separator: ","), action)
            guard available.contains(action) else {
                DispatchQueue.main.async { completion(false, right ? "这个图标没有暴露右键菜单操作；已临时显示，可在顶栏右键。" : "这个图标没有辅助功能点击接口；已临时显示，可在顶栏点击。") }; return
            }
            let result = AXUIElementPerformAction(item.element, action as CFString)
            NSLog("MBAR action result %@ code=%d", item.bundle, result.rawValue)
            DispatchQueue.main.async { completion(result == .success, result == .success ? nil : "系统未能打开这个菜单（AX \(result.rawValue)）；图标已临时显示，可从顶栏操作。") }
        }
    }
    private static func hostWindows() -> [AXUIElement] {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) else { return [] }
        let root = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        return children(root).filter { role($0) == kAXWindowRole }
    }
    private static func hostedFrame(_ item: MenuItem, display: CGRect) -> CGRect? {
        // Multiple buttons in one application cannot be mapped by PID alone.
        let root = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard extras(root).count == 1 else { return nil }
        return hostedFrames([item], display: display)[item.id]
    }
    private static func hostedFrames(_ items: [MenuItem], display: CGRect) -> [String: CGRect] {
        struct Group { let rect: CGRect; let owners: Set<pid_t> }
        var samples: [pid_t: [HostedFrameSample]] = [:]
        let wanted = Set(items.map(\.pid))
        for window in hostWindows() {
            let groups: [Group] = children(window).compactMap { group in
                guard let rect = frame(group), display.contains(rect), rect.height > 2, rect.width > 2 else { return nil }
                let owners = Set(children(group).compactMap { child -> pid_t? in
                    var pid: pid_t = 0; AXUIElementGetPid(child, &pid); return pid > 0 ? pid : nil
                })
                return Group(rect: rect, owners: owners)
            }
            for pid in wanted {
                var candidates: [CGRect] = []
                for group in groups where group.owners.contains(pid) {
                    if !candidates.contains(group.rect) { candidates.append(group.rect) }
                }
                if candidates.count == 1, let rect = candidates.first {
                    samples[pid, default: []].append(.init(frame: rect, neighbours: groups.filter { !$0.owners.contains(pid) }.map(\.rect)))
                }
            }
        }
        var result: [String: CGRect] = [:]
        for item in items {
            if let rect = HostedGeometry.resolve(samples[item.pid] ?? [], screen: display) { result[item.id] = rect }
        }
        return result
    }
    private static func revealOverflow(display: CGRect) -> Bool {
        setOverflow(expanded: true, display: display)
    }
    private static func setOverflow(expanded: Bool, display: CGRect) -> Bool {
        var candidates: [AXUIElement] = []
        for window in hostWindows() {
            for child in children(window) where role(child) == kAXButtonRole {
                guard let rect = frame(child), display.contains(rect) else { continue }
                let text = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute(child, $0) as? String }
                let hideNames = ["Hide Menu Bar Items", "Hide Hidden Menu Bar Items", "隐藏菜单栏项目", "隐藏菜单栏项"]
                let showNames = ["Show Hidden Menu Bar Items", "显示隐藏的菜单栏项目", "显示隐藏的菜单栏项"]
                if text.contains(where: { (expanded ? hideNames : showNames).contains($0) }) { continue }
                if text.contains(where: { (expanded ? showNames : hideNames).contains($0) }) { candidates.append(child) }
            }
        }
        guard let button = candidates.first else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }
    private static func clickHostedItem(_ item: MenuItem, right: Bool, display: CGRect) -> Bool {
        var initial = hostedFrame(item, display: display)
        if initial == nil, revealOverflow(display: display) {
            let deadline = Date().addingTimeInterval(0.8)
            repeat {
                Thread.sleep(forTimeInterval: 0.05)
                initial = hostedFrame(item, display: display)
            } while initial == nil && Date() < deadline
        }
        guard let first = initial else { return false }
        Thread.sleep(forTimeInterval: 0.06)
        guard let point = ClickGeometry.point(first: first, current: hostedFrame(item, display: display), screen: display),
              let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let button: CGMouseButton = right ? .right : .left
        guard let down = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseDown : .leftMouseDown, mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseUp : .leftMouseUp, mouseCursorPosition: point, mouseButton: button) else { return false }
        // One exact click; no drag, cursor lock, event interception or retry.
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.025)
        up.post(tap: .cghidEventTap)
        return true
    }

}

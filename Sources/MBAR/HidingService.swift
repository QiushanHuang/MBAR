import Foundation
import MBARBridge
import MBARCore

struct HidingRuntime {
    var available: () -> Bool
    var create: ([String], @escaping (Error?) -> Void) -> AnyObject?
    var release: (AnyObject?) -> Void

    static let system = HidingRuntime(
        available: { MBARHidingAvailable() },
        create: { allowed, completion in MBARCreateAssertion(allowed, completion) as AnyObject? },
        release: { MBARReleaseAssertion($0) })
}

@MainActor final class HidingService {
    private let runtime: HidingRuntime
    private var handles: [Int: AnyObject] = [:]
    private var leases = AssertionLifecycle()
    private struct Request: Equatable {
        let allowed: [String]
        let hostPID: Int
    }
    private var requested: Request?
    private(set) var suspended = false
    private(set) var state = VisibilityState()
    var onChange: ((VisibilityState.Phase, String?) -> Void)?
    init(runtime: HidingRuntime = .system) { self.runtime = runtime }
    var available: Bool { runtime.available() }
    private func release(_ ids: [Int]) {
        for id in ids { runtime.release(handles.removeValue(forKey: id)) }
    }
    func suspendForSystemChange() {
        suspended = true
        requested = nil
        // Retain active/pending protection. Releasing everything during a
        // display transition would briefly reveal Always-hide items.
    }
    func resumeAfterSystemChange() { suspended = false }
    func restore() {
        requested = nil
        state.restore()
        release(leases.restore())
        onChange?(.visible, nil)
    }
    func hide(running: Set<String>, selected: Set<String>, own: String, hostPID: Int) {
        guard !suspended, hostPID > 0 else { return }
        guard !selected.isEmpty else { restore(); return }
        guard available else { onChange?(state.phase, "当前系统的隐藏接口不可用。"); return }
        let allowed = MenuPolicy.allowed(running: running, hidden: selected, own: own).sorted()
        let request = Request(allowed: allowed, hostPID: hostPID)
        // Deduplicate within a host process only. A replacement MenuBarAgent
        // cannot inherit the previous process's native assertion.
        guard requested != request else { return }
        requested = request
        let token = state.begin()
        release(leases.begin(token))
        onChange?(.activating, nil)
        // Keep the old assertion until its replacement is active: always-hidden
        // items must not be revealed between snapshot and menu transitions.
        let handle = runtime.create(allowed) { [weak self] error in
            DispatchQueue.main.async { self?.complete(token, error: error) }
        }
        if let handle { handles[token] = handle }
        else { complete(token, error: NSError(domain: "MBAR", code: 1, userInfo: [NSLocalizedDescriptionKey: "系统未创建隐藏会话"])) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.state.generation == token, self.state.phase == .activating else { return }
            self.complete(token, error: NSError(domain: "MBAR", code: 2, userInfo: [NSLocalizedDescriptionKey: "隐藏接口响应超时"]))
        }
    }
    private func complete(_ token: Int, error: Error?) {
        // Keep a successful lease as protection even if its callback arrives
        // during sleep/reflow. Do not publish a settled state or an error from
        // that environment; the next settled request must still rebind it.
        if suspended {
            // If an older active lease exists, retain it as well: the pending
            // request may be a temporary reveal cancelled by the transition.
            if error == nil, handles[token] != nil, leases.active == nil {
                release(leases.complete(token, success: true))
            }
            return
        }
        let isCurrent = state.generation == token && state.phase == .activating
        release(leases.complete(token, success: error == nil && handles[token] != nil))
        guard isCurrent else { return }
        if error != nil { requested = nil }
        state.finish(token, succeeded: leases.active != nil)
        onChange?(state.phase, error.map { "\($0.localizedDescription)。保留原显示状态，可点“显示全部”恢复。" })
    }
}

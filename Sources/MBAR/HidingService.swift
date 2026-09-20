import Foundation
import MBARBridge
import MBARCore

@MainActor final class HidingService {
    private var handles: [Int: AnyObject] = [:]
    private var leases = AssertionLifecycle()
    private var requestedAllowed: [String]?
    private(set) var state = VisibilityState()
    var onChange: ((VisibilityState.Phase, String?) -> Void)?
    var available: Bool { MBARHidingAvailable() }
    private func release(_ ids: [Int]) {
        for id in ids { MBARReleaseAssertion(handles.removeValue(forKey: id)) }
    }
    func restore() {
        requestedAllowed = nil
        state.restore()
        release(leases.restore())
        onChange?(.visible, nil)
    }
    func hide(running: Set<String>, selected: Set<String>, own: String) {
        guard !selected.isEmpty else { restore(); return }
        guard available else { onChange?(state.phase, "当前系统的隐藏接口不可用。"); return }
        let allowed = MenuPolicy.allowed(running: running, hidden: selected, own: own).sorted()
        // Repeating an identical native assertion can restart macOS animations.
        guard requestedAllowed != allowed else { return }
        requestedAllowed = allowed
        let token = state.begin()
        release(leases.begin(token))
        onChange?(.activating, nil)
        // Keep the old assertion until its replacement is active: always-hidden
        // items must not be revealed between snapshot and menu transitions.
        let handle = MBARCreateAssertion(allowed) { [weak self] error in
            DispatchQueue.main.async { self?.complete(token, error: error) }
        } as AnyObject?
        if let handle { handles[token] = handle }
        else { complete(token, error: NSError(domain: "MBAR", code: 1, userInfo: [NSLocalizedDescriptionKey: "系统未创建隐藏会话"])) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.state.generation == token, self.state.phase == .activating else { return }
            self.complete(token, error: NSError(domain: "MBAR", code: 2, userInfo: [NSLocalizedDescriptionKey: "隐藏接口响应超时"]))
        }
    }
    private func complete(_ token: Int, error: Error?) {
        let isCurrent = state.generation == token && state.phase == .activating
        release(leases.complete(token, success: error == nil && handles[token] != nil))
        guard isCurrent else { return }
        if error != nil { requestedAllowed = nil }
        state.finish(token, succeeded: leases.active != nil)
        onChange?(state.phase, error.map { "\($0.localizedDescription)。保留原显示状态，可点“显示全部”恢复。" })
    }
}

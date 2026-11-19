import AppKit
import ApplicationServices
import MBARCore

struct NativeIconPreview {
    let prepared: PreparedNativeIcon
    let identity: IconAppIdentity
    let pid: pid_t
    let capturedAt: Date
}
struct NativeIconBatch {
    var icons: [String: PreparedNativeIcon] = [:]
    var failure: String?
}

@MainActor enum NativeIconCapture {
    static func capture(_ item: MenuItem) async throws -> PreparedNativeIcon {
        func failure(_ text: String) -> NSError { NSError(domain: "MBAR.NativeIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        guard AXIsProcessTrusted() else { throw failure("需要辅助功能权限来确认原生图标的位置。") }
        let discovery = MenuDiscovery()
        let batch = try await sample([item], frames: { await discovery.visibleFrames($0) },
                                      capture: { await IconCapture().capture($0) })
        guard let prepared = batch.icons[item.id] else {
            throw failure(batch.failure ?? "未取得完整原生图标，请重试。")
        }
        return prepared
    }

    /// Snapshot an entire batch once. Accept each crop only if the same item occupied
    /// exactly the same rectangle in all three observations on the same display.
    static func sample(_ items: [MenuItem],
                       frames: ([MenuItem]) async -> [MenuItem],
                       capture: ([MenuItem]) async -> CapturedIcons) async throws -> NativeIconBatch {
        func unchanged(_ previous: [MenuItem], _ current: [MenuItem]) -> [MenuItem] {
            let byID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
            return current.filter { item in
                guard let old = byID[item.id], let rect = old.frame else { return false }
                return item.pid == old.pid && item.frame == rect && CFEqual(item.element, old.element)
            }
        }
        guard !items.isEmpty else { return NativeIconBatch() }
        let first = await frames(items)
        try Task.checkCancellation()
        guard !first.isEmpty else { return NativeIconBatch(failure: "图标当前不可见或位置不明确。请先让图标在系统菜单栏中可见。") }
        try await Task.sleep(nanoseconds: 100_000_000)
        let stable = unchanged(first, await frames(first))
        try Task.checkCancellation()
        guard !stable.isEmpty else { return NativeIconBatch(failure: "菜单栏位置仍在变化，稳定后可重试。") }
        let captured = await capture(stable)
        try Task.checkCancellation()
        if let error = captured.error { throw error }
        var result: [String: PreparedNativeIcon] = [:]
        let final = unchanged(stable, await frames(stable))
        try Task.checkCancellation()
        guard !final.isEmpty else { return NativeIconBatch(failure: "采样期间菜单栏布局发生变化，请重试。") }
        for item in final {
            guard let image = captured.images[item.id],
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            result[item.id] = NativeIconQuality.prepare(cg, sourcePointSize: image.size)
        }
        return NativeIconBatch(icons: result, failure: result.isEmpty ? captured.failure ?? "图像可能被遮挡、裁切或淡化，请检查菜单栏再试。" : nil)
    }
}

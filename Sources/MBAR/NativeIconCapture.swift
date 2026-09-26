import AppKit
import ApplicationServices
import MBARCore

struct NativeIconPreview {
    let prepared: PreparedNativeIcon
    let identity: IconAppIdentity
    let pid: pid_t
    let capturedAt: Date
}
@MainActor enum NativeIconCapture {
    static func capture(_ item: MenuItem) async throws -> PreparedNativeIcon {
        func failure(_ text: String) -> NSError { NSError(domain: "MBAR.NativeIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        guard AXIsProcessTrusted() else { throw failure("需要辅助功能权限来确认原生图标的位置。") }
        let discovery = MenuDiscovery()
        guard let first = await discovery.visibleFrames([item]).first, let firstRect = first.frame else {
            throw failure("图标目前不可见或位置不明确。请先让该应用的原生图标可见，再读取；MBAR 不会为取图展开系统栏。")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        guard let stable = await discovery.visibleFrames([item]).first, stable.frame == firstRect else {
            throw failure("菜单栏位置仍在变化，请稳定后重试。")
        }
        let capture = await IconCapture().capture([stable])
        try Task.checkCancellation()
        if let error = capture.error { throw error }
        guard let final = await discovery.visibleFrames([item]).first, final.frame == firstRect else {
            throw failure("取图期间位置发生变化，本次图像已丢弃。")
        }
        guard let image = capture.images[item.id], let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let prepared = NativeIconQuality.prepare(cg) else {
            throw failure(capture.failure ?? "未取得完整透明图标，可能处于遮挡、裁切或淡化状态。本次图像未采用。")
        }
        return prepared
    }
}

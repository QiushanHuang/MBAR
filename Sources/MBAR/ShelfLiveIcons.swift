import AppKit
import ApplicationServices
import MBARCore

struct ShelfLiveImage {
    let image: NSImage
    let pid: pid_t
    let element: AXUIElement
    let source: String
    let value: String?

    init(_ image: NSImage, item: MenuItem, source: String, value: String? = nil) {
        self.value = value
        self.image = image
        pid = item.pid
        element = item.element
        self.source = source
    }
}

@MainActor final class ShelfLiveIcons {
    private var task: Task<Void, Never>?
    // Passive AX reads must not queue ahead of an explicit menu click.
    private let discovery = MenuDiscovery()
    private let statusText = ShelfStatusText()

    func stop(model: AppModel) {
        task?.cancel()
        task = nil
        model.replaceLiveImages([:])
    }

    func start(model: AppModel, display: CGRect) {
        stop(model: model)
        model.shelfLiveNotice = nil
        model.shelfLivePermissionDenied = false
        guard model.shelfLiveIcons else { return }
        task = Task {
            var permissionDenied = false
            while !Task.isCancelled && model.shelfLiveIcons && model.shelfVisible?() == true {
                let items = model.collected.filter(model.shelfLiveEligible)
                var samples: [String: ShelfLiveImage] = [:]
                if !permissionDenied {
                    do {
                        let captures = try await NativeIconCapture.sample(items, frames: {
                            await self.discovery.visibleFrames($0, display: display)
                        }, capture: { await IconCapture().capture($0, recordGeometry: false) })
                        try Task.checkCancellation()
                        for item in items {
                            guard let prepared = captures.icons[item.id] else { continue }
                            let mapping = model.iconLibrary.savedMapping(for: item)
                            let mode = mapping?.origin == .nativeSnapshot ? mapping?.mode ?? prepared.mode : prepared.mode
                            if let image = IconLibrary.image(prepared.image.png, mode: mode, pointSize: prepared.pointSize) {
                                samples[item.id] = ShelfLiveImage(image, item: item, source: "可见原生图标 · 定期刷新")
                            }
                        }
                        model.shelfLiveNotice = nil
                    } catch {
                        guard !Task.isCancelled else { return }
                        permissionDenied = ScreenCaptureAccess.isPermissionDenied(error)
                        model.shelfLivePermissionDenied = permissionDenied
                        model.shelfLiveNotice = permissionDenied
                            ? "请允许屏幕录制，然后重新打开下拉栏以刷新原生图标。"
                            : "原生图标读取失败，稍后自动重试。"
                    }
                }
                let remaining = items.filter { samples[$0.id] == nil }
                let statusSamples = await statusText.samples(for: remaining, library: model.iconLibrary)
                guard !Task.isCancelled, model.shelfLiveIcons, model.shelfVisible?() == true else { return }
                samples.merge(statusSamples) { native, _ in native }
                model.replaceLiveImages(samples)
                do { try await Task.sleep(for: samples.isEmpty ? .seconds(5) : .seconds(2)) }
                catch { return }
            }
        }
    }
}

import AppKit
import Combine
import MBARCore

struct IconApplication {
    let identity: IconAppIdentity
    let resources: URL
    let pid: pid_t
    let itemCount: Int
    let item: MenuItem?
    var bundle: String { identity.bundleID }
}
enum IconSourceState: String {
    case idle = "等待识别", discovering = "正在寻找", verified = "已适配 · 静态", automatic = "自动匹配 · 静态"
    case userSelected = "用户选择 · 静态", custom = "自定义 · 静态", needsSelection = "待选择"
    case missing = "未找到", stale = "需要重新选择", multiple = "多个菜单项目暂不支持", failed = "读取失败"
}
struct IconEntry {
    var state: IconSourceState = .idle
    var image: NSImage?
    var source = ""
    var message = ""
    var candidates: [IconCandidate] = []
    var scanned = false
    var scanning = false
    var complete = false
    var mapping: IconMapping?
}
private final class IconCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
/// One queue bounds work across applications. Returned objects are immutable data, not AppKit views.
private final class IconResourceWorker {
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "local.qiushan.MBAR.icon-resources"; queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    func run<T>(priority: Bool = false, _ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let operation = BlockOperation { continuation.resume(returning: work()) }
            operation.queuePriority = priority ? .veryHigh : .normal
            queue.addOperation(operation)
        }
    }
}
@MainActor final class IconLibrary: ObservableObject {
    @Published private(set) var entries: [String: IconEntry] = [:]
    @Published private(set) var storageError: String?
    var onChange: (() -> Void)?
    private let worker = IconResourceWorker()
    private var store: IconMappingStore?
    let directory: URL
    var imports: URL { directory.appendingPathComponent("ImportedIcons", isDirectory: true) }
    private var apps: [String: IconApplication] = [:]
    private var stamps: [String: String] = [:]
    private var gate = IconRequestGate()
    private var tasks: [String: Task<Void, Never>] = [:]
    private var cancellations: [String: IconCancellation] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MBAR", isDirectory: true)
        do { store = try IconMappingStore(directory: self.directory) }
        catch { storageError = "无法读取图标选择记录，原文件已保留：\(error.localizedDescription)" }
    }
    func entry(_ bundle: String) -> IconEntry { entries[bundle] ?? IconEntry() }
    func canUndo(_ bundle: String) -> Bool { apps[bundle].map { store?.canUndo(for: $0.identity.key) == true } ?? false }
    func hasOverride(_ bundle: String) -> Bool {
        guard let app = apps[bundle], let mapping = store?.mapping(for: app.identity.key) else { return false }
        return mapping.origin != .automatic
    }
    func reconcile(_ items: [MenuItem], priority: Set<String>) {
        let grouped = Dictionary(grouping: items, by: \.bundle)
        for bundle in Array(apps.keys) where grouped[bundle] == nil { remove(bundle) }
        for bundle in grouped.keys.sorted(by: { priority.contains($0) == priority.contains($1) ? $0 < $1 : priority.contains($0) }) {
            guard let group = grouped[bundle], let item = group.first,
                  let url = NSRunningApplication(processIdentifier: item.pid)?.bundleURL,
                  let appBundle = Bundle(url: url), let resources = appBundle.resourceURL else { continue }
            let identity = IconAppIdentity(bundleID: bundle, path: url.resolvingSymlinksInPath().path,
                version: appBundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
                shortVersion: appBundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            request(IconApplication(identity: identity, resources: resources, pid: item.pid, itemCount: group.count, item: item))
        }
    }
    private func stamp(_ app: IconApplication) -> String {
        func metadata(_ url: URL) -> String {
            let value = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return "\(value?.fileSize ?? -1):\(value?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        let mapping = store?.mapping(for: app.identity.key)
        let resourceStamp = mapping.map {
            let root: URL
            if case .imported = $0.locator { root = imports } else { root = app.resources }
            return metadata(root.appendingPathComponent($0.locator.resourcePath))
        } ?? ""
        let liveTitle = app.bundle == "io.github.clash-verge-rev.clash-verge-rev" ? app.item?.title ?? "" : ""
        return "\(app.identity.key):\(app.identity.version):\(app.identity.shortVersion):\(app.pid):\(app.itemCount):\(metadata(app.resources)):\(resourceStamp):\(liveTitle)"
    }
    func request(_ app: IconApplication, force: Bool = false, includeCandidates: Bool = false) {
        apps[app.bundle] = app
        let currentStamp = stamp(app)
        if !force, stamps[app.bundle] == currentStamp {
            if tasks[app.bundle] != nil || !includeCandidates || entry(app.bundle).scanned { return }
        }
        cancel(app.bundle)
        stamps[app.bundle] = currentStamp
        let token = gate.begin(app.bundle)
        let cancellation = IconCancellation(); cancellations[app.bundle] = cancellation
        let previous = entry(app.bundle)
        if includeCandidates && !force && previous.image != nil {
            entries[app.bundle]?.scanning = true
        } else {
            entries[app.bundle] = IconEntry(state: app.itemCount == 1 ? .discovering : .multiple, scanning: app.itemCount == 1)
        }
        onChange?()
        guard app.itemCount == 1 else { return }
        tasks[app.bundle] = Task { [weak self] in
            guard let self else { return }
            let loaded = await self.resolve(app, cancellation: cancellation, includeCandidates: includeCandidates)
            guard self.gate.accepts(app.bundle, token: token), !Task.isCancelled, !cancellation.cancelled else { return }
            var final = loaded
            if let mapping = final.mapping, mapping.origin == .automatic {
                do { try self.store?.set(mapping, for: app.identity.key, userInitiated: false) }
                catch { final.message += " 自动匹配可用，但缓存保存失败：\(error.localizedDescription)" }
            }
            self.entries[app.bundle] = final
            self.stamps[app.bundle] = self.stamp(app)
            self.tasks.removeValue(forKey: app.bundle); self.cancellations.removeValue(forKey: app.bundle)
            self.onChange?()
        }
    }
    private func resolve(_ app: IconApplication, cancellation: IconCancellation, includeCandidates: Bool, ignoringOverride: Bool = false) async -> IconEntry {
        var output = IconEntry()
        let mapping = ignoringOverride ? nil : store?.mapping(for: app.identity.key)
        let imports = self.imports
        func load(_ mapping: IconMapping) async -> IconEntry? {
            let decoded: IconDecodedImage? = await worker.run(priority: includeCandidates) {
                guard !cancellation.cancelled,
                      let data = IconResourceDiscovery.read(mapping.locator, resources: app.resources, imports: imports),
                      mapping.validation(current: app.identity, digest: IconDigest.sha256(data)) == .valid else { return nil }
                return IconImageDecoder.decode(data, path: mapping.locator.label)
            }
            guard let decoded else { return nil }
            return IconEntry(state: mapping.origin == .custom ? .custom : (mapping.origin == .userSelected ? .userSelected : .automatic),
                image: Self.image(decoded.png, mode: mapping.mode), source: mapping.locator.label, mapping: mapping)
        }
        if let mapping, mapping.origin != .automatic {
            if let restored = await load(mapping) { output = restored }
            else { output = IconEntry(state: .stale, message: "原来选择的图像已变化或无法读取，请重新选择。", mapping: mapping) }
        } else {
            if let item = app.item, !cancellation.cancelled {
                let loaded = await VerifiedMenuIconSource().load([item])
                if let image = loaded.images[item.id] {
                    output = IconEntry(state: .verified, image: image, source: loaded.sources[item.id] ?? "已验证的应用适配")
                }
            }
            if output.image == nil, let mapping, let restored = await load(mapping) { output = restored }
        }
        guard !cancellation.cancelled else { return output }
        if output.image != nil && !includeCandidates { return output }
        let scan = await worker.run(priority: includeCandidates) { IconResourceDiscovery.scan(resources: app.resources, cancelled: { cancellation.cancelled }) }
        output.candidates = Self.groupedCandidates(scan.candidates)
        output.scanned = true; output.complete = scan.complete
        let issues = scan.issues.joined(separator: "；")
        if !issues.isEmpty { output.message += (output.message.isEmpty ? "" : "\n") + issues + "。可选择已找到的图标或重新扫描。" }
        if output.image == nil && output.state != .stale {
            if let index = IconRanker.automaticIndex(scan.candidates.map(\.evidence), complete: scan.complete, itemCount: app.itemCount) {
                let candidate = scan.candidates[index]
                let selected = IconMapping(identity: app.identity, locator: candidate.locator, digest: candidate.evidence.digest, mode: candidate.suggestedMode, origin: .automatic)
                output.image = Self.image(candidate.image.png, mode: selected.mode)
                output.source = candidate.locator.label; output.state = .automatic; output.mapping = selected
            } else { output.state = scan.candidates.isEmpty ? .missing : .needsSelection }
        }
        return output
    }
    private static func groupedCandidates(_ candidates: [IconCandidate]) -> [IconCandidate] {
        var digests: Set<String> = [], families: Set<String> = []
        // A scale family requires strict naming, matching logical dimensions, and matching normalized pixels.
        return candidates.filter {
            let distinct = digests.insert($0.evidence.digest).inserted
            let newFamily = $0.evidence.family.map { families.insert($0).inserted } ?? true
            return distinct && newFamily
        }
    }
    static func image(_ data: Data, mode: IconDisplayMode) -> NSImage? {
        guard let image = NSImage(data: data), image.size.height > 0 else { return nil }
        let ratio = min(1, 22 / image.size.height)
        image.size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        image.isTemplate = mode == .template
        return image
    }
    func scanCandidates(_ bundle: String, force: Bool = false) {
        guard let app = apps[bundle] else { return }
        request(app, force: force || tasks[bundle] != nil, includeCandidates: true)
    }
    func fallbackDescription(_ bundle: String) async -> String {
        guard let app = apps[bundle] else { return "应用已退出，恢复后将在再次运行时重新匹配。" }
        let fallback = await resolve(app, cancellation: IconCancellation(), includeCandidates: false, ignoringOverride: true)
        if fallback.image != nil { return "将回退到\(fallback.state.rawValue)：\(fallback.source)。" }
        return "将回退到“\(fallback.state.rawValue)”，保留图标设置入口。"
    }
    func stopScan(_ bundle: String) {
        cancel(bundle)
        var current = entry(bundle); current.scanning = false
        if current.state == .discovering { current.state = .idle; current.message = "扫描已取消，可重新扫描。" }
        entries[bundle] = current; stamps.removeValue(forKey: bundle); onChange?()
    }
    func choose(_ candidate: IconCandidate, mode: IconDisplayMode, bundle: String) async throws {
        guard let app = apps[bundle], app.itemCount == 1 else { throw CocoaError(.fileNoSuchFile) }
        cancel(bundle)
        let token = gate.begin(bundle)
        let imports = self.imports
        let valid = await worker.run(priority: true) {
            IconResourceDiscovery.read(candidate.locator, resources: app.resources, imports: imports).map { IconDigest.sha256($0) == candidate.evidence.digest } ?? false
        }
        guard gate.accepts(bundle, token: token), apps[bundle]?.identity == app.identity else { throw CancellationError() }
        guard valid else { throw NSError(domain: "MBAR", code: 1, userInfo: [NSLocalizedDescriptionKey: "候选资源已变化，请重新扫描后选择。"] ) }
        let mapping = IconMapping(identity: app.identity, locator: candidate.locator, digest: candidate.evidence.digest, mode: mode, origin: .userSelected)
        try save(mapping, app: app)
    }
    func importImage(_ url: URL) async throws -> IconDecodedImage {
        let decoded = await worker.run(priority: true) { () -> IconDecodedImage? in
            guard ["png", "tif", "tiff", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize, size <= 8_388_608,
                  let data = try? Data(contentsOf: url) else { return nil }
            return IconImageDecoder.decode(data, path: url.lastPathComponent)
        }
        guard let decoded else { throw NSError(domain: "MBAR", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取图片：请使用不超过 8 MiB、16 MP 的 PNG、TIFF 或 JPEG。"] ) }
        return decoded
    }
    func saveImport(_ decoded: IconDecodedImage, mode: IconDisplayMode, bundle: String) throws {
        guard let app = apps[bundle], app.itemCount == 1, store != nil else { throw CocoaError(.fileWriteUnknown) }
        let digest = IconDigest.sha256(decoded.png), filename = digest + ".png"
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        try decoded.png.write(to: imports.appendingPathComponent(filename), options: .atomic)
        try save(IconMapping(identity: app.identity, locator: .imported(filename), digest: digest, mode: mode, origin: .custom), app: app)
    }
    private func save(_ mapping: IconMapping, app: IconApplication) throws {
        guard let store else { throw CocoaError(.fileWriteUnknown) }
        try store.set(mapping, for: app.identity.key)
        request(app, force: true, includeCandidates: true)
    }
    func reset(_ bundle: String) throws {
        guard let app = apps[bundle], let store else { throw CocoaError(.fileWriteUnknown) }
        try store.set(nil, for: app.identity.key)
        request(app, force: true, includeCandidates: true)
    }
    func undo(_ bundle: String) throws {
        guard let app = apps[bundle], let store else { throw CocoaError(.fileWriteUnknown) }
        try store.undo(for: app.identity.key)
        request(app, force: true, includeCandidates: true)
    }
    func remove(_ bundle: String) {
        cancel(bundle); apps.removeValue(forKey: bundle); stamps.removeValue(forKey: bundle); entries.removeValue(forKey: bundle)
        onChange?()
    }
    func shutdown() { for bundle in Array(tasks.keys) { cancel(bundle) } }
    private func cancel(_ bundle: String) {
        gate.invalidate(bundle); cancellations.removeValue(forKey: bundle)?.cancel()
        tasks.removeValue(forKey: bundle)?.cancel()
    }
}

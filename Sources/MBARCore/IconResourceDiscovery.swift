import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct IconDecodedImage: Sendable {
    public let png: Data
    public let width: Int
    public let height: Int
    public let transparent: Bool
    public let previewDigest: String
    public var menuSized: Bool { width >= 8 && height >= 8 && width <= 512 && height <= 512 && Double(width) / Double(height) >= 0.25 && Double(width) / Double(height) <= 4 }
}
public enum IconImageDecoder {
    public static func decode(_ data: Data, path: String) -> IconDecodedImage? {
        guard !data.isEmpty, data.count <= 8_388_608 else { return nil }
        var sourceWidth = 0, sourceHeight = 0
        let image: CGImage?
        if URL(fileURLWithPath: path).pathExtension.lowercased() == "pdf" {
            guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider),
                  pdf.numberOfPages == 1, let page = pdf.page(at: 1) else { return nil }
            let bounds = page.getBoxRect(.mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width >= 1, bounds.height >= 1,
                  bounds.width <= 4096, bounds.height <= 4096, bounds.width * bounds.height <= 16_000_000 else { return nil }
            sourceWidth = Int(bounds.width); sourceHeight = Int(bounds.height)
            let scale = min(2, 128 / max(bounds.width, bounds.height))
            guard let context = context(width: max(1, Int(bounds.width * scale)), height: max(1, Int(bounds.height * scale))) else { return nil }
            context.scaleBy(x: scale, y: scale); context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.drawPDFPage(page); image = context.makeImage()
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16_000_000 / height else { return nil }
            sourceWidth = width; sourceHeight = height
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        }
        guard let image, let context = context(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var transparent = false, visible = false
        for i in 0..<(image.width * image.height) {
            let alpha = bytes[i * 4 + 3]
            transparent = transparent || alpha < 250; visible = visible || alpha > 8
        }
        guard visible, let normalized = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, normalized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        guard let comparison = self.context(width: 64, height: 64) else { return nil }
        comparison.interpolationQuality = .none
        comparison.draw(normalized, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let pixels = comparison.data else { return nil }
        return IconDecodedImage(png: output as Data, width: sourceWidth, height: sourceHeight, transparent: transparent,
                                previewDigest: IconDigest.sha256(Data(bytes: pixels, count: 64 * 64 * 4)))
    }
    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    }
}
public struct IconCandidate: Identifiable, Sendable {
    public let locator: IconLocator
    public let evidence: IconEvidence
    public let image: IconDecodedImage
    public let sourceRevision: String?
    public var id: String { locator.label }
    public var suggestedMode: IconDisplayMode { evidence.template ? .template : .original }
    public init(locator: IconLocator, evidence: IconEvidence, image: IconDecodedImage, sourceRevision: String? = nil) {
        self.locator = locator; self.evidence = evidence; self.image = image; self.sourceRevision = sourceRevision
    }
}
public struct IconDiscoveryResult: Sendable {
    public var candidates: [IconCandidate] = []
    public var complete = true
    public var issues: [String] = []
    public init() {}
}
public struct IconScanLimits: Sendable {
    public var maxEntries: Int
    public var maxCandidates: Int
    public var seconds: TimeInterval
    public init(maxEntries: Int = 5_000, maxCandidates: Int = 64, seconds: TimeInterval = 2) {
        self.maxEntries = maxEntries; self.maxCandidates = maxCandidates; self.seconds = seconds
    }
}
public enum IconResourceDiscovery {
    public static let extensions: Set<String> = ["png", "tif", "tiff", "pdf", "ico"]
    /// Resolve each component without following symbolic links, including imported image paths.
    public static func safeURL(_ path: String, under root: URL) -> URL? {
        guard ASARResource.validPath(path) else { return nil }
        var url = root.standardizedFileURL
        for part in path.split(separator: "/") {
            url.appendPathComponent(String(part))
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true else { return nil }
        }
        guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { return nil }
        return url
    }
    public static func read(_ locator: IconLocator, resources: URL, imports: URL) -> Data? {
        let root: URL
        if case .imported = locator { root = imports } else { root = resources }
        guard let url = safeURL(locator.resourcePath, under: root) else { return nil }
        switch locator {
        case .file, .imported: return readImage(url)
        case .catalog(let name): return IconCatalog.read(name: name, resources: resources)
        case .asar(_, let entry):
            guard let archive = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return ASARResource.extract(from: archive, path: entry)
        }
    }
    private static func readImage(_ url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= 8_388_608 else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
    public static func sourceRevision(_ locator: IconLocator, resources: URL) -> String? {
        guard case .catalog = locator, let url = safeURL("Assets.car", under: resources),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 536_870_912,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return IconDigest.sha256(data)
    }
    public static func scan(resources: URL, limits: IconScanLimits = IconScanLimits(), cancelled: () -> Bool = { false }) -> IconDiscoveryResult {
        let root = resources.resolvingSymlinksInPath().standardizedFileURL
        let app = root.deletingLastPathComponent().deletingLastPathComponent()
        let appStem = app.pathExtension == "app" ? IconEvidence.tokens(app.deletingPathExtension().lastPathComponent).joined() : ""
        func matchesAppName(_ path: String) -> Bool {
            let stem = IconEvidence.tokens(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent).joined()
            return appStem.count >= 3 && stem.hasPrefix(appStem)
        }
        var result = IconDiscoveryResult()
        let deadline = ProcessInfo.processInfo.systemUptime + limits.seconds
        var entries = 0
        struct Pending {
            let path: String
            let locator: IconLocator
            let declaredTemplate: Bool
            let revision: String?
            let read: () -> (Data, Bool)?
            var evidence: IconEvidence { IconEvidence(path: path, digest: "", transparent: false, menuSized: false, declaredTemplate: declaredTemplate) }
        }
        var pending: [Pending] = []
        func issue(_ message: String) {
            result.complete = false
            if !result.issues.contains(message), result.issues.count < 8 { result.issues.append(message) }
        }
        func stopped() -> Bool {
            if cancelled() { issue("扫描已取消"); return true }
            if ProcessInfo.processInfo.systemUptime >= deadline { issue("达到扫描时间上限"); return true }
            return false
        }
        func collect(_ path: String, locator: IconLocator, read: @escaping () -> Data?) {
            let evidence = IconEvidence(path: path, digest: "", transparent: false, menuSized: false)
            guard extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()), !evidence.excluded,
                  evidence.worthInspecting || matchesAppName(path) else { return }
            pending.append(Pending(path: path, locator: locator, declaredTemplate: false, revision: nil, read: { read().map { ($0, false) } }))
        }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Assets.car").path), !stopped() {
            do {
                let listing = try IconCatalog.list(resources: root, seconds: max(0.01, deadline - ProcessInfo.processInfo.systemUptime), maxNames: limits.maxEntries, cancelled: cancelled)
                if !listing.complete { issue("图像资源库索引不完整") }
                guard let revision = sourceRevision(.catalog(""), resources: root) else { throw CocoaError(.fileReadUnknown) }
                entries += listing.assets.count
                for asset in listing.assets where IconEvidence(path: asset.name, digest: "", transparent: false, menuSized: false).worthInspecting {
                    pending.append(Pending(path: asset.name, locator: .catalog(asset.name), declaredTemplate: asset.isTemplate,
                        revision: revision, read: { IconCatalog.readImage(name: asset.name, resources: root).map { ($0.data, $0.isTemplate) } }))
                }
            } catch { issue("无法完整读取图像资源库（Assets.car）") }
        }
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in issue("部分资源无法读取"); return true }) {
            for case let url as URL in enumerator {
                if stopped() { break }
                entries += 1
                guard entries <= limits.maxEntries else { issue("资源条目达到上限"); break }
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { issue("部分资源无法读取"); continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); issue("已跳过符号链接"); continue }
                let normalized = url.resolvingSymlinksInPath().standardizedFileURL
                guard normalized.path.hasPrefix(root.path + "/") else { issue("资源路径超出应用目录"); continue }
                let relative = String(normalized.path.dropFirst(root.path.count + 1))
                if values.isDirectory == true {
                    if ["app", "framework", "bundle"].contains(url.pathExtension.lowercased()) || url.lastPathComponent == "Frameworks" { enumerator.skipDescendants(); continue }
                    if relative.split(separator: "/").count >= 12 { enumerator.skipDescendants(); issue("目录深度达到上限") }
                    continue
                }
                if url.lastPathComponent == "app.asar" {
                    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                          let index = try? ASARResource.index(from: data, maxEntries: max(1, limits.maxEntries - entries)) else { issue("图标归档损坏或无法读取"); continue }
                    if !index.complete { issue("归档扫描不完整或包含不支持的跳转") }
                    for path in index.paths { collect(path, locator: .asar(archive: relative, entry: path)) { index.extract(path) } }
                    entries += index.paths.count
                } else { collect(relative, locator: .file(relative)) { readImage(url) } }
            }
        } else { issue("无法读取应用资源目录") }
        pending.sort {
            if $0.evidence.score != $1.evidence.score { return $0.evidence.score > $1.evidence.score }
            return $0.locator.label < $1.locator.label
        }
        if pending.count > limits.maxCandidates { issue("候选数量达到上限，已优先读取菜单图标") }
        for candidate in pending.prefix(max(0, limits.maxCandidates)) {
            if stopped() { break }
            guard let payload = candidate.read(), let image = IconImageDecoder.decode(payload.0, path: candidate.path) else { issue("部分候选无法读取或解码"); continue }
            // App-name-only hints are manual candidates, and only for small transparent artwork.
            if !candidate.evidence.worthInspecting && (!image.menuSized || !image.transparent) { continue }
            let bytes = payload.0
            let stem = (candidate.path as NSString).deletingPathExtension
            let scale = stem.hasSuffix("@2x") ? 2 : (stem.hasSuffix("@3x") ? 3 : 1)
            let base = stem.replacingOccurrences(of: "@[123]x$", with: "", options: .regularExpression)
            let family = image.width % scale == 0 && image.height % scale == 0
                ? "\(base):\(image.width / scale)x\(image.height / scale):\(image.previewDigest)" : nil
            let evidence = IconEvidence(path: candidate.path, digest: IconDigest.sha256(bytes), transparent: image.transparent,
                menuSized: image.menuSized, family: family, declaredTemplate: candidate.declaredTemplate || payload.1)
            result.candidates.append(IconCandidate(locator: candidate.locator, evidence: evidence, image: image, sourceRevision: candidate.revision))
        }
        _ = stopped()
        result.candidates.sort {
            if $0.evidence.score != $1.evidence.score { return $0.evidence.score > $1.evidence.score }
            let firstFamily = $0.evidence.family ?? $0.id, secondFamily = $1.evidence.family ?? $1.id
            if firstFamily != secondFamily { return firstFamily < secondFamily }
            if $0.image.width != $1.image.width { return $0.image.width > $1.image.width }
            return $0.id < $1.id
        }
        return result
    }
}

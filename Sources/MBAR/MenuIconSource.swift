import AppKit
import MBARCore

struct LoadedMenuIcons {
    var images: [String: NSImage] = [:]
    var sources: [String: String] = [:]
    var failures: [String: String] = [:]
}

/// Reads the owning app's menu-bar artwork, never its application icon and never
/// a crop of the screen. Only known resource names or verified embedded images
/// are accepted. Does not load/execute another bundle's executable.
@MainActor final class MenuIconSource {
    private var cache: [String: NSImage] = [:]
    private var cacheSources: [String: String] = [:]

    func load(_ items: [MenuItem]) async -> LoadedMenuIcons {
        var result = LoadedMenuIcons()
        let counts = Dictionary(grouping: items, by: \.bundle).mapValues(\.count)
        for item in items {
            guard !Task.isCancelled else { break }
            // A single app resource cannot identify several distinct items.
            guard counts[item.bundle] == 1 else {
                result.failures[item.id] = "此应用有多个菜单项目，需要分别适配"; continue
            }
            guard let appURL = NSRunningApplication(processIdentifier: item.pid)?.bundleURL,
                  let bundle = Bundle(url: appURL) else {
                result.failures[item.id] = "应用已退出或无法读取其资源位置"; continue
            }
            let version = bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
            let key = "\(item.bundle):\(item.pid):\(version)"
            var image = cache[key]
            var source = cacheSources[key]
            var failure = "尚未适配此应用的菜单图标来源"
            if image == nil {
                var resource: String?
                switch item.bundle {
                case "info.marcel-dierkes.KeepingYouAwake": resource = "InactiveIcon"
                case "app.monitorcontrol.MonitorControl": resource = "status"
                case "io.tailscale.ipn.macsys": resource = "StatusBarIcon"
                case "com.drbuho.disktool.BuhoNTFSMenu": resource = "menuicon"
                case "com.netease.uuremote": resource = "StatusIcon"
                default: break
                }
                if let resource {
                    failure = "应用的菜单图标资源名称或格式已变化"
                    image = bundle.image(forResource: NSImage.Name(resource))?.copy() as? NSImage
                    source = "菜单栏原始资源：\(resource)（静态）"
                } else if item.bundle == "com.openai.codex",
                          let url = bundle.url(forResource: "chatgptTemplate@2x", withExtension: "png") {
                    image = NSImage(contentsOf: url)
                    image?.size = NSSize(width: 18, height: 18); image?.isTemplate = true
                    source = "菜单栏原始资源：chatgptTemplate@2x.png（静态）"
                } else if item.bundle == "studio.qiushan.ScreenPilot" {
                    // Verified in ScreenPilot's status-item creation code.
                    image = NSImage(systemSymbolName: "display.2", accessibilityDescription: item.name)
                    image?.size = NSSize(width: 24, height: 20)
                    source = "菜单栏原始符号：display.2（静态）"
                } else if ["com.electron.dockerdesktop", "com.ugreen.pro.client"].contains(item.bundle),
                          let resources = bundle.resourceURL {
                    let path = item.bundle == "com.electron.dockerdesktop"
                        ? "assets/tray/darwin/statusItemIcon-0Template@2x.png" : "icon/ugreen_tray_normal.png"
                    let archiveURL = resources.appendingPathComponent("app.asar")
                    let data = await Task.detached(priority: .userInitiated) {
                        guard let archive = try? Data(contentsOf: archiveURL, options: .mappedIfSafe) else { return Optional<Data>.none }
                        return ASARResource.extract(from: archive, path: path)
                    }.value
                    if let data, let decoded = NSImage(data: data), decoded.size.height > 0 {
                        let height: CGFloat = 22
                        decoded.size = NSSize(width: decoded.size.width * height / decoded.size.height, height: height)
                        decoded.isTemplate = true
                        image = decoded; source = "菜单栏原始资源：\(path)（静态）"
                    }
                    failure = "菜单图标归档缺失、已变化或完整性检查失败"
                } else if let executable = bundle.executableURL {
                    let descriptor: (prefix: Data, count: Int, hash: String, name: String, size: CGFloat)?
                    switch item.bundle {
                    case "com.crystalidea.macsfancontrol":
                        descriptor = (Data([137,80,78,71,13,10,26,10]), 1005,
                            "5dbdc40e40fae554d05eeb5ddf4a9aa71120d96175f8771a9a82b446ac604815", "tray_grey@2x.png", 18)
                    case "io.github.clash-verge-rev.clash-verge-rev":
                        descriptor = (Data([0,0,1,0]), 15215,
                            "3017229ff26e3176c77eb57a925906546b4fe6b76755a80d254c49314774a691", "tray-icon-mono.ico", 20)
                    default: descriptor = nil
                    }
                    if let descriptor {
                        failure = "内置菜单图标已变化，需要更新资源适配"
                        let data = await Task.detached(priority: .userInitiated) {
                            guard let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path),
                                  let size = attributes[.size] as? NSNumber, size.intValue <= 536_870_912,
                                  let binary = try? Data(contentsOf: executable, options: .mappedIfSafe) else { return Optional<Data>.none }
                            return EmbeddedIcon.extract(from: binary, prefix: descriptor.prefix,
                                                        length: descriptor.count, sha256: descriptor.hash)
                        }.value
                        if let data {
                            image = NSImage(data: data)
                            image?.size = NSSize(width: descriptor.size, height: descriptor.size)
                            image?.isTemplate = true
                            source = "内置菜单栏资源：\(descriptor.name)（完整性已校验，静态）"
                        }
                    }
                }
                if let image, image.isValid, image.size.width > 0, image.size.height > 0 {
                    cache[key] = image; cacheSources[key] = source
                } else { image = nil }
            }
            guard let image else { result.failures[item.id] = failure; continue }
            // Use the exposed text once per opening. This is semantic data,
            // not a promise to reproduce the app's custom drawing/layout.
            if item.bundle == "io.github.clash-verge-rev.clash-verge-rev", item.title.contains("B/s") {
                result.images[item.id] = Self.withStatusText(image, text: item.title)
                result.sources[item.id] = "\(source ?? "原始菜单图标")；数值读取自本次辅助功能标题"
            } else {
                result.images[item.id] = image
                result.sources[item.id] = source
            }
        }
        // Do not retain resources for exited/replaced applications indefinitely.
        let livePrefixes = items.map { "\($0.bundle):\($0.pid):" }
        cache = cache.filter { key, _ in livePrefixes.contains { key.hasPrefix($0) } }
        cacheSources = cacheSources.filter { cache[$0.key] != nil }
        return result
    }

    private static func withStatusText(_ icon: NSImage, text: String) -> NSImage {
        let lines = text.split(separator: "|").prefix(2).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.black
        ]
        let width = ceil(lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0)
        let size = NSSize(width: icon.size.width + 4 + width, height: 24)
        let output = NSImage(size: size, flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: (size.height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            for (index, line) in lines.enumerated() {
                let y: CGFloat = lines.count == 1 ? 6 : (index == 0 ? 12 : 1)
                (line as NSString).draw(at: NSPoint(x: icon.size.width + 4, y: y), withAttributes: attributes)
            }
            return true
        }
        output.isTemplate = true
        return output
    }
}

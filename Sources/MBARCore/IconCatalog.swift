import Foundation
import AppKit
import Darwin

public enum BoundedToolOutput {
    /// Runs only a named local helper. File-backed output avoids pipe deadlocks and caps memory use.
    public static func run(executable: String, arguments: [String], seconds: TimeInterval, maxBytes: Int,
                           cancelled: () -> Bool = { false }) throws -> Data {
        guard seconds > 0, maxBytes > 0, !cancelled() else { throw CocoaError(.userCancelled) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MBAR-tool-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        task.standardOutput = handle; task.standardError = FileHandle.nullDevice
        try task.run()
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        var stopped = false
        while task.isRunning {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if cancelled() || ProcessInfo.processInfo.systemUptime >= deadline || size > maxBytes {
                stopped = true; task.terminate()
                // The helper has no children. Kill only this process if it ignores SIGTERM.
                Thread.sleep(forTimeInterval: 0.02)
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                break
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        task.waitUntilExit()
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard !stopped, task.terminationStatus == 0, size <= maxBytes else { throw CocoaError(.fileReadUnknown) }
        return try Data(contentsOf: file)
    }
}
public enum IconCatalog {
    public struct Asset: Sendable {
        public let name: String
        public var isTemplate: Bool
    }
    public struct Listing: Sendable {
        public var assets: [Asset]
        public var complete: Bool
    }
    public struct Image: Sendable {
        public let data: Data
        public let isTemplate: Bool
    }
    public static func parse(_ data: Data, maxNames: Int = 5_000) throws -> Listing {
        guard data.count <= 16_777_216,
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        var names: [String: Bool] = [:], complete = true
        for row in rows {
            guard let type = row["AssetType"] as? String, ["Image", "Vector", "Vector Glyph", "SVG", "PDF"].contains(type) else { continue }
            guard let name = row["Name"] as? String, validName(name) else { complete = false; continue }
            if names[name] == nil && names.count >= maxNames { complete = false; continue }
            names[name] = (names[name] ?? false) || (row["Template Mode"] as? String == "template")
        }
        return Listing(assets: names.keys.sorted().map { Asset(name: $0, isTemplate: names[$0]!) }, complete: complete)
    }
    public static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 512 && ASARResource.validPath(name)
    }
    public static func list(resources: URL, seconds: TimeInterval, maxNames: Int, cancelled: () -> Bool) throws -> Listing {
        guard let url = IconResourceDiscovery.safeURL("Assets.car", under: resources),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 536_870_912 else { throw CocoaError(.fileReadTooLarge) }
        let data = try BoundedToolOutput.run(executable: "/usr/bin/assetutil", arguments: ["-I", url.path], seconds: seconds,
                                            maxBytes: 16_777_216, cancelled: cancelled)
        return try parse(data, maxNames: maxNames)
    }
    public static func read(name: String, resources: URL) -> Data? {
        readImage(name: name, resources: resources)?.data
    }
    public static func readImage(name: String, resources: URL) -> Image? {
        guard validName(name), IconResourceDiscovery.safeURL("Assets.car", under: resources) != nil else { return nil }
        let appURL = resources.deletingLastPathComponent().deletingLastPathComponent()
        guard let bundle = Bundle(url: appURL),
              bundle.resourceURL?.resolvingSymlinksInPath().standardizedFileURL == resources.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        // This AppKit method reads data from the bundle; never call load(), dlopen(), or its executable.
        return autoreleasepool {
            var output: Image?
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                guard let image = bundle.image(forResource: NSImage.Name(name)),
                      image.size.width > 0, image.size.height > 0,
                      image.size.width <= 4096, image.size.height <= 4096,
                      image.size.width * image.size.height <= 16_000_000 else { return }
                let scale = min(2, 256 / max(image.size.width, image.size.height))
                let width = max(1, Int(ceil(image.size.width * scale))), height = max(1, Int(ceil(image.size.height * scale)))
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: width * 4, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                defer { NSGraphicsContext.restoreGraphicsState() }
                image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero,
                           operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
                if let data = rep.representation(using: .png, properties: [:]) {
                    output = Image(data: data, isTemplate: image.isTemplate)
                }
            }
            return output
        }
    }
}

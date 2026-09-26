#if DEBUG
import AppKit
import SwiftUI
import MBARCore

/// Development-only UI harness. Uses fixtures and a temporary store; never changes hiding or production preferences.
@MainActor enum IconSettingsPreview {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MBAR-IconPreview-" + UUID().uuidString)
        let resources = root.appendingPathComponent("Example.app/Contents/Resources/tray")
        do {
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            for (name, symbol) in [("trayTemplate.png", "sun.max.fill"), ("otherTrayTemplate.png", "moon.fill"), ("trayDisconnectedTemplate.png", "network.slash")] {
                let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
                    NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.draw(in: NSRect(x: 3, y: 3, width: 26, height: 26))
                    return true
                }
                if let tiff = image.tiffRepresentation, let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try data.write(to: resources.appendingPathComponent(name))
                }
            }
            let library = IconLibrary(directory: root.appendingPathComponent("Store"))
            let identity = IconAppIdentity(bundleID: "local.mbar.preview", path: root.appendingPathComponent("Example.app").path, version: "1", shortVersion: "1.0")
            let args = CommandLine.arguments
            let option = args.firstIndex(of: "--preview-bundle")
            let selectedBundle = option.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            let liveApp = selectedBundle.flatMap { id in NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id } }
            let displayBundle = liveApp?.bundleIdentifier ?? identity.bundleID
            let displayName = liveApp?.localizedName ?? "Example"
            if liveApp == nil {
                library.request(IconApplication(identity: identity, resources: resources.deletingLastPathComponent(), pid: getpid(), itemCount: 1, item: nil))
            } else {
                if let liveApp, let url = liveApp.bundleURL, let bundle = Bundle(url: url), let resources = bundle.resourceURL {
                    let liveIdentity = IconAppIdentity(bundleID: displayBundle, path: url.resolvingSymlinksInPath().path,
                        version: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
                        shortVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    library.request(IconApplication(identity: liveIdentity, resources: resources, pid: liveApp.processIdentifier, itemCount: 1, item: nil), includeCandidates: true)
                }
                MenuDiscovery().scan { snapshot in
                    guard snapshot.error == nil else { return }
                    MainActor.assumeIsolated {
                        library.reconcile(snapshot.items.filter { $0.bundle == displayBundle }, priority: [displayBundle])
                        library.scanCandidates(displayBundle)
                    }
                }
            }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 614, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "MBAR 图标适配 · 开发预览"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: IconSettingsView(library: library, bundle: displayBundle, name: displayName, dismiss: { app.terminate(nil) }))
            window.center(); window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            print("Preview fixture: \(root.path)")
            withExtendedLifetime((window, library)) { app.run() }
        } catch { fputs("Preview failed: \(error)\n", stderr) }
    }
}
#endif

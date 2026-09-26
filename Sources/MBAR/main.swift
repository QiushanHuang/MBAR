import AppKit
import ApplicationServices
import MBARBridge
import MBARCore
import Darwin

if let request = AppRelaunchRequest(arguments: CommandLine.arguments) {
    let deadline = ProcessInfo.processInfo.systemUptime + 6
    func parentIsAlive() -> Bool { kill(request.parentPID, 0) == 0 || errno == EPERM }
    while parentIsAlive(), ProcessInfo.processInfo.systemUptime < deadline { usleep(50_000) }
    if parentIsAlive() { exit(75) }
}

#if DEBUG
if CommandLine.arguments.contains("--icon-settings-preview") || Bundle.main.bundleIdentifier == "local.qiushan.MBAR.IconPreview" {
    MainActor.assumeIsolated { IconSettingsPreview.run() }
    exit(0)
}
#endif

if CommandLine.arguments.contains("--diagnostics") {
    print("MBAR \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("accessibility: \(AXIsProcessTrusted())")
    print("screenCapture: \(CGPreflightScreenCaptureAccess())")
    print("hidingAPI: \(MBARHidingAvailable())")
    if CommandLine.arguments.contains("--items") {
        let discovery = MenuDiscovery()
        var finished = false
        discovery.scan { snapshot in
            for item in snapshot.items {
                var actions: CFArray?
                AXUIElementCopyActionNames(item.element, &actions)
                print("item=\(item.bundle) id=\(item.id) role=\(MenuDiscovery.role(item.element)) frame=\(String(describing: item.frame)) actions=\(actions as? [String] ?? [])")
            }
            if let error = snapshot.error { print(error) }
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if !finished { print("enumeration timed out"); exit(2) }
    }
    exit(0)
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

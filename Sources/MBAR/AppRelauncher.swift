import AppKit

@MainActor enum AppRelauncher {
    static var available: Bool { Bundle.main.bundleIdentifier == "local.qiushan.MBAR" && Bundle.main.bundleURL.pathExtension == "app" }
    static func restart(iconBundle: String) throws {
        guard available, let executable = Bundle.main.executableURL else { throw CocoaError(.executableNotLoadable) }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--relaunch-parent", String(getpid()), "--reopen-icon-settings", iconBundle]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        // The child waits for this process to exit before it creates any menu-bar state.
        NSApp.terminate(nil)
    }
}

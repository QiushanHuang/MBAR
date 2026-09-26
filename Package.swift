// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MBAR", platforms: [.macOS(.v14)],
    products: [.executable(name: "MBAR", targets: ["MBAR"])],
    targets: [
        .target(name: "MBARCore"),
        .target(name: "MBARBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("Foundation")]),
        .executableTarget(name: "MBAR", dependencies: ["MBARCore", "MBARBridge"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ScreenCaptureKit")]),
        .testTarget(name: "MBARCoreTests", dependencies: ["MBARCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MBARIntegrationTests", dependencies: ["MBAR", "MBARCore"])
    ], swiftLanguageModes: [.v5])

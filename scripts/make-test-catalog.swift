// Regenerate the original (non-third-party) asset catalog fixture used by IconCatalogTests.
// Run from the repository root: swift scripts/make-test-catalog.swift
import AppKit
let fm = FileManager.default
let temporary = fm.temporaryDirectory.appendingPathComponent("MBAR-catalog-fixture-" + UUID().uuidString)
defer { try? fm.removeItem(at: temporary) }
let assets = temporary.appendingPathComponent("Fixture.xcassets")
let target = URL(fileURLWithPath: "Tests/MBARCoreTests/Fixtures/CatalogFixture.bundle")
let resources = target.appendingPathComponent("Contents/Resources")
try fm.createDirectory(at: resources, withIntermediateDirectories: true)
for name in ["StatusBarIcon", "ToolbarIcon"] {
    let folder = assets.appendingPathComponent(name + ".imageset")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
        NSColor.black.setFill(); NSRect(x: 6, y: 4, width: 12, height: 16).fill(); return true
    }
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try png.write(to: folder.appendingPathComponent("icon.png"))
    let metadata: [String: Any] = ["info": ["version": 1, "author": "xcode"], "images": [["idiom": "mac", "filename": "icon.png", "scale": "1x"]], "properties": ["template-rendering-intent": "template"]]
    try JSONSerialization.data(withJSONObject: metadata).write(to: folder.appendingPathComponent("Contents.json"))
}
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]]).write(to: assets.appendingPathComponent("Contents.json"))
let info = ["CFBundleIdentifier": "local.mbar.catalog-test", "CFBundleName": "CatalogFixture", "CFBundlePackageType": "BNDL"]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: target.appendingPathComponent("Contents/Info.plist"))
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
process.arguments = ["actool", "--platform", "macosx", "--minimum-deployment-target", "14.0", "--compile", resources.path, assets.path]
try process.run(); process.waitUntilExit()
exit(process.terminationStatus)

import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let factor = CGFloat(side) / 1024
        let transform = AffineTransform(scale: factor)
        (transform as NSAffineTransform).concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
        NSGradient(starting: NSColor(calibratedRed: 0.025, green: 0.30, blue: 0.36, alpha: 1),
                   ending: NSColor(calibratedRed: 0.08, green: 0.72, blue: 0.69, alpha: 1))!.draw(in: tile, angle: 55)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        tile.lineWidth = 2; tile.stroke()
        NSColor.white.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: NSRect(x: 208, y: 655, width: 608, height: 66), xRadius: 28, yRadius: 28).fill()
        let panel = NSBezierPath(roundedRect: NSRect(x: 240, y: 298, width: 544, height: 220), xRadius: 48, yRadius: 48)
        NSColor.white.withAlphaComponent(0.20).setFill(); panel.fill()
        for x in [340, 472, 604] {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 379, width: 80, height: 60), xRadius: 15, yRadius: 15).fill()
        }
        let arrow = NSBezierPath(); arrow.move(to: CGPoint(x: 468, y: 596)); arrow.line(to: CGPoint(x: 512, y: 554)); arrow.line(to: CGPoint(x: 556, y: 596))
        arrow.lineWidth = 25; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        NSColor.white.setStroke(); arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

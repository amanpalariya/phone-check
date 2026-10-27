import AppKit
import Foundation

// Source geometry matches the Android adaptive icon; each platform keeps its own packaging.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let factor = CGFloat(size) / 1024
        let tile = NSBezierPath(roundedRect: NSRect(x: 100 * factor, y: 100 * factor, width: 824 * factor, height: 824 * factor), xRadius: 182 * factor, yRadius: 182 * factor)
        NSColor(srgbRed: 0.45, green: 0.28, blue: 0.79, alpha: 1).setFill(); tile.fill()
        let phone = NSBezierPath(roundedRect: NSRect(x: 350 * factor, y: 230 * factor, width: 324 * factor, height: 564 * factor), xRadius: 48 * factor, yRadius: 48 * factor)
        phone.lineWidth = 38 * factor
        NSColor.white.setStroke(); phone.stroke()
        let details = NSBezierPath()
        details.move(to: NSPoint(x: 454 * factor, y: 724 * factor)); details.line(to: NSPoint(x: 570 * factor, y: 724 * factor))
        details.move(to: NSPoint(x: 488 * factor, y: 302 * factor)); details.line(to: NSPoint(x: 536 * factor, y: 302 * factor))
        details.lineCapStyle = .round; details.lineWidth = 30 * factor; details.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

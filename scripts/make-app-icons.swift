import AppKit
import Foundation

// Run from the repository root: swift scripts/make-app-icons.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("assets/app-icon.png")
guard let sourceBitmap = NSBitmapImageRep(data: try Data(contentsOf: source)),
      let sourceImage = sourceBitmap.cgImage else {
    fatalError("Cannot load assets/app-icon.png; run from the repository root")
}

// Normalize the transparent source margin before applying platform-specific padding.
// Keep the master artwork unchanged, including its antialiased edges.
// Sparse extraction speckles must not count as padding or shrink the actual tile.
var columns = [Int](repeating: 0, count: sourceBitmap.pixelsWide)
var rows = [Int](repeating: 0, count: sourceBitmap.pixelsHigh)
for y in 0..<sourceBitmap.pixelsHigh {
    for x in 0..<sourceBitmap.pixelsWide {
        if (sourceBitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
            columns[x] += 1; rows[y] += 1
        }
    }
}
let columnThreshold = max(2, sourceBitmap.pixelsHigh * 3 / 100)
let rowThreshold = max(2, sourceBitmap.pixelsWide * 3 / 100)
guard let left = columns.firstIndex(where: { $0 >= columnThreshold }),
      let right = columns.lastIndex(where: { $0 >= columnThreshold }),
      let top = rows.firstIndex(where: { $0 >= rowThreshold }),
      let bottom = rows.lastIndex(where: { $0 >= rowThreshold }) else { fatalError("App artwork is empty") }
let pixelBounds = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
let crop = pixelBounds.insetBy(dx: -1, dy: -1).intersection(
    CGRect(x: 0, y: 0, width: sourceBitmap.pixelsWide, height: sourceBitmap.pixelsHigh))
guard let cropped = sourceImage.cropping(to: crop) else { fatalError("Cannot trim app artwork") }
let artwork = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))

func writePNG(to url: URL, size: Int, inset: CGFloat = 0.04) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.current!.cgContext.clear(canvas)
    let bounds = canvas.insetBy(dx: CGFloat(size) * inset, dy: CGFloat(size) * inset)
    let scale = min(bounds.width / artwork.size.width, bounds.height / artwork.size.height)
    let fitted = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
    artwork.draw(in: NSRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                           width: fitted.width, height: fitted.height))
    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = temporary.appendingPathComponent("PhoneCheck.iconset")
defer { try? FileManager.default.removeItem(at: temporary) }
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try writePNG(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), size: points * scale)
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("macos/Resources/PhoneCheck.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// A 108 dp adaptive layer at xxxhdpi, with 64 dp artwork inside the central 66 dp safe zone.
// https://developer.android.com/develop/ui/compose/system/icon_design_adaptive
try writePNG(to: root.appendingPathComponent("android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"),
             size: 432, inset: 22.0 / 108.0)

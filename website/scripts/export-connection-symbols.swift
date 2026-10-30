import AppKit

// The exact native SF Symbols used by Phone Check's connection indicator.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ["wifi", "cloud"] {
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 200, weight: .medium))!
    let size = NSSize(width: 640, height: 500)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 1000,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let rect = NSRect(x: (size.width-symbol.size.width)/2, y: (size.height-symbol.size.height)/2,
                      width: symbol.size.width, height: symbol.size.height)
    symbol.draw(in: rect)
    let tint = name == "wifi"
        ? NSColor(calibratedRed: 137/255, green: 209/255, blue: 251/255, alpha: 1)
        : NSColor(calibratedRed: 185/255, green: 205/255, blue: 250/255, alpha: 1)
    tint.setFill()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: destination.appendingPathComponent("native-\(name).png"))
}

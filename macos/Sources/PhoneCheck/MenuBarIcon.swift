import AppKit

/// Phone and message-card artwork, with an optional monochrome unread badge.
enum MenuBarIcon {
    static func image(hasNew: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 20), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let phone = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 11.5, height: 16), xRadius: 3, yRadius: 3)
            phone.lineWidth = 1.5; phone.stroke()
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 15.6, width: 3.5, height: 1.2), xRadius: 0.6, yRadius: 0.6).fill()

            let card = NSBezierPath(roundedRect: NSRect(x: 6, y: 1.5, width: 15.5, height: 11.5), xRadius: 3.2, yRadius: 3.2)
            // Occlude the phone behind the card without sampling the menu-bar background.
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill(); card.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.labelColor.setStroke(); card.lineWidth = 1.5; card.stroke()
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 6, width: 3.2, height: 3.2)).fill()
            for (y, width) in [(8.0, 6.0), (5.2, 4.6)] {
                NSBezierPath(roundedRect: NSRect(x: 12.7, y: y, width: width, height: 1.35), xRadius: 0.675, yRadius: 0.675).fill()
            }
            if hasNew {
                NSGraphicsContext.current?.compositingOperation = .copy
                NSColor.clear.setFill()
                NSBezierPath(ovalIn: NSRect(x: 16.2, y: 9.3, width: 7.6, height: 7.6)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: 17, y: 10.1, width: 6, height: 6)).fill()
            }
            return true
        }
        // Both states follow native menu-bar tinting, including the unread badge.
        image.isTemplate = true
        return image
    }
}

import AppKit
import ImageIO
import UniformTypeIdentifiers
import PhoneCheckCore

// Decode only bounded JPEG previews. Never interpret a path or URL supplied by the phone.
enum NoticeImage {
    static func data(_ notice: Notice) -> Data? {
        decode(notice.image, maxBytes: 32768, type: UTType.jpeg.identifier, maxDimension: 1024)
    }
    static func image(_ notice: Notice) -> NSImage? { data(notice).flatMap(NSImage.init(data:)) }
    static func icon(_ notice: Notice) -> NSImage? {
        decode(notice.appIcon, maxBytes: 12288, type: UTType.png.identifier, maxDimension: 96).flatMap(NSImage.init(data:))
    }
    static func actionIcon(_ action: NoticeAction) -> NSImage? {
        decode(action.icon, maxBytes: 12288, type: UTType.png.identifier, maxDimension: 96).flatMap(NSImage.init(data:))
    }
    private static func decode(_ encoded: String?, maxBytes: Int, type: String, maxDimension: Int) -> Data? {
        guard let encoded, encoded.count <= (maxBytes * 4 / 3 + 4),
              let bytes = Data(base64Encoded: encoded), bytes.count <= maxBytes,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetType(source) as String? == type,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maxDimension, height <= maxDimension else { return nil }
        return bytes
    }
}

// Legacy action identifiers remain readable by the integration harness.
enum NotificationAlerts {
    static let dismiss = "DISMISS_ON_PHONE"
    static let open = "OPEN_ON_PHONE"
    static let actionPrefix = "PHONE_ACTION:"
}

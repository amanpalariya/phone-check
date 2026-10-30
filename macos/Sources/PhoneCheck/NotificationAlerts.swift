import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import UserNotifications
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

final class NotificationAlerts {
    static let dismiss = "DISMISS_ON_PHONE"
    static let open = "OPEN_ON_PHONE"
    static let actionPrefix = "PHONE_ACTION:"
    private let center: UNUserNotificationCenter
    private var registered: Set<String> = []
    init(center: UNUserNotificationCenter) { self.center = center }
    func register(_ notices: [Notice]) {
        var categories: Set<UNNotificationCategory> = [fixed(true), fixed(false)]
        // Bound category churn. Every action remains available in the companion.
        for notice in notices.prefix(64) { categories.insert(category(notice)) }
        registered = Set(categories.map(\.identifier))
        center.setNotificationCategories(categories)
    }
    private func fixed(_ dismissible: Bool) -> UNNotificationCategory {
        UNNotificationCategory(identifier: dismissible ? "PHONE_CHECK" : "PHONE_CHECK_FIXED",
            actions: dismissible ? [UNNotificationAction(identifier: Self.dismiss, title: "Dismiss on phone", options: [.authenticationRequired])] : [],
            intentIdentifiers: [], options: [])
    }
    private func identifier(_ notice: Notice) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(notice.actions ?? [])) ?? Data()
        let hash = SHA256.hash(data: data + Data([notice.dismissible ? 1 : 0, notice.openable == true ? 1 : 0]))
        return "PC_" + hash.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    private func category(_ notice: Notice) -> UNNotificationCategory {
        var actions: [UNNotificationAction] = (notice.actions ?? []).filter(\.enabled).prefix(3).map { action in
            var options: UNNotificationActionOptions = [.authenticationRequired]
            if action.destructive { options.insert(.destructive) }
            let id = Self.actionPrefix + action.id
            if action.input && action.freeform {
                return UNTextInputNotificationAction(identifier: id, title: action.title, options: options,
                    textInputButtonTitle: "Send", textInputPlaceholder: "Reply")
            }
            if action.input { options.insert(.foreground) }
            return UNNotificationAction(identifier: id, title: action.title, options: options)
        }
        if notice.openable == true && actions.count < 3 {
            actions.append(UNNotificationAction(identifier: Self.open, title: "Open on phone", options: [.authenticationRequired]))
        }
        if notice.dismissible { actions.append(UNNotificationAction(identifier: Self.dismiss, title: "Dismiss on phone", options: [.authenticationRequired])) }
        return UNNotificationCategory(identifier: identifier(notice), actions: actions, intentIdentifiers: [], options: [])
    }
    func deliver(_ notice: Notice, isNew: Bool, onError: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = notice.app; content.subtitle = notice.title; content.body = notice.alertText
        content.threadIdentifier = notice.groupKey ?? notice.packageName ?? notice.app
        content.interruptionLevel = isNew ? .active : .passive
        let id = identifier(notice)
        content.categoryIdentifier = registered.contains(id) ? id : (notice.dismissible ? "PHONE_CHECK" : "PHONE_CHECK_FIXED")
        content.userInfo = ["key": notice.key, "revision": notice.revision]
        var temporary: URL?
        if let data = NoticeImage.data(notice) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                try data.write(to: url, options: .atomic)
                temporary = url
                content.attachments = [try UNNotificationAttachment(identifier: "preview", url: url)]
            } catch { try? FileManager.default.removeItem(at: url) }
        }
        let request = UNNotificationRequest(identifier: notice.key, content: content, trigger: nil)
        center.add(request) { error in
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
            if error != nil { DispatchQueue.main.async(execute: onError) }
        }
    }
}

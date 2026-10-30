import Foundation

public struct NoticeAction: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var input: Bool
    public var freeform: Bool
    public var choices: [String]
    public var enabled: Bool
    public var requiresUnlock: Bool
    public var revision: String? = nil
    public var mediaControl: String? = nil
    public var icon: String? = nil
    public var destructive: Bool
}
public struct NoticeMessage: Codable, Equatable {
    public var sender: String
    public var text: String
    public var time: Int64
    public var attachment: Bool
}
public struct NoticeProgress: Codable, Equatable {
    public var value: Int
    public var max: Int
    public var indeterminate: Bool
}
public struct NoticeMedia: Codable, Equatable {
    public var playing: Bool
    public var buffering: Bool
    public var position: Int64
    public var duration: Int64
    public var speed: Double
    public var updatedAt: Int64
    public func position(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince1970 * 1000 - Double(updatedAt))
        let value = max(0, Double(position) + (playing ? elapsed * speed : 0))
        return duration > 0 ? min(Double(duration), value) : value
    }
}
public struct Notice: Codable, Equatable, Identifiable {
    public var key: String
    public var app: String
    public var title: String
    public var body: String
    public var revision: String
    public var dismissible: Bool
    public var postedAt: Int64
    public var appIcon: String?
    public var packageName: String?
    public var kind: String?
    public var lines: [String]?
    public var messages: [NoticeMessage]?
    public var progress: NoticeProgress?
    public var media: NoticeMedia?
    public var image: String?
    public var ongoing: Bool?
    public var groupKey: String?
    public var groupSummary: Bool?
    public var openable: Bool?
    public var actions: [NoticeAction]?
    public var id: String { key }
    public init(key: String, app: String, title: String, body: String, revision: String,
                dismissible: Bool, postedAt: Int64) {
        self.key = key; self.app = app; self.title = title; self.body = body
        self.revision = revision; self.dismissible = dismissible; self.postedAt = postedAt
    }
    public var isMedia: Bool { kind == "media" }
    public var alertText: String {
        if let messages, !messages.isEmpty {
            return messages.map { "\($0.sender): \($0.text.isEmpty && $0.attachment ? "Attachment" : $0.text)" }.joined(separator: "\n")
        }
        if let lines, !lines.isEmpty { return lines.joined(separator: "\n") }
        if let progress {
            return body + (progress.indeterminate ? "\nIn progress" : "\n\(progress.value) / \(progress.max)")
        }
        return body
    }
}

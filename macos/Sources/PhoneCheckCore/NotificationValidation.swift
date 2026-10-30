import Foundation

// Wire limits live with the models so transport and presentation share one policy.
extension Notice {
    public var isValid: Bool {
        guard !key.isEmpty, key.utf8.count <= 4096,
              app.count <= 256, title.count <= 2048, body.count <= 8192,
              revision.count == 64,
              (image?.count ?? 0) <= 44000,
              (appIcon?.count ?? 0) <= 16400,
              (groupKey?.count ?? 0) <= 4096,
              (actions?.count ?? 0) <= (isMedia ? 12 : 6),
              (lines?.count ?? 0) <= 20,
              (messages?.count ?? 0) <= 12 else { return false }

        if let lines, !lines.allSatisfy({ $0.count <= 1024 }) { return false }
        if let messages, !messages.allSatisfy(\.isValid) { return false }
        if let progress, !progress.isValid { return false }
        if let media, !isMedia || !media.isValid { return false }
        if let actions {
            guard Set(actions.map(\.id)).count == actions.count else { return false }
            return actions.allSatisfy(\.isValid)
        }
        return true
    }
}

private extension NoticeMessage {
    var isValid: Bool { sender.count <= 256 && text.count <= 2048 }
}

private extension NoticeProgress {
    var isValid: Bool { max >= 0 && value >= 0 && value <= Swift.max(1, max) }
}

private extension NoticeMedia {
    var isValid: Bool {
        position >= 0 && duration >= 0 && updatedAt >= 0 &&
            speed.isFinite && abs(speed) <= 16
    }
}

private extension NoticeAction {
    var isValid: Bool {
        !id.isEmpty && id.count <= 64 && title.count <= 128 &&
            (revision == nil || revision?.count == 64) &&
            (icon?.count ?? 0) <= 16400 && (mediaControl?.count ?? 0) <= 32 &&
            choices.count <= 8 && choices.allSatisfy { $0.count <= 256 }
    }
}

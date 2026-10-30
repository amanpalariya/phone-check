import Foundation
import Combine
import PhoneCheckCore

/// Owns in-flight commands and transient UI feedback. It never retains notification history.
final class NotificationCommandController: ObservableObject {
    static let feedbackDelay: TimeInterval = 0.4
    struct ReplyTarget: Equatable { var key: String; var action: String }
    struct Removal { var key: String; var revision: String }
    private struct Pending { var key: String; var revision: String; var kind: String; var timer: Timer; var feedbackTimer: Timer }
    private(set) var pendingKeys: Set<String> = []
    // Admission is immediate; visible busy feedback waits to avoid flashing on fast actions.
    @Published private(set) var busyKeys: Set<String> = []
    @Published private(set) var feedback: [String: String] = [:]
    @Published private(set) var error: String?
    @Published var replyTarget: ReplyTarget?
    @Published var replyDraft = ""
    private var pending: [String: Pending] = [:]
    private let current: (String) -> Notice?
    private let connected: () -> Bool
    private let send: (Message) -> Void

    init(current: @escaping (String) -> Notice?, connected: @escaping () -> Bool, send: @escaping (Message) -> Void) {
        self.current = current; self.connected = connected; self.send = send
    }
    func reset() {
        pending.values.forEach { $0.timer.invalidate(); $0.feedbackTimer.invalidate() }; pending = [:]
        pendingKeys = []; busyKeys = []; feedback = [:]; error = nil; replyTarget = nil; replyDraft = ""
    }
    func notificationChanged(_ notice: Notice) {
        clearFeedback(notice.key)
        for (id, command) in Array(pending) where command.kind == "dismiss" && command.key == notice.key && command.revision != notice.revision {
            finish(id, error: "Notification changed")
        }
        if let target = replyTarget, target.key == notice.key, notice.actions?.contains(where: { $0.id == target.action }) != true {
            replyTarget = nil // Keep the draft for an explicit retry on the updated notification.
        }
    }
    func notificationRemoved(_ key: String) {
        clearFeedback(key)
        if replyTarget?.key == key { replyTarget = nil; replyDraft = "" }
        for (id, command) in Array(pending) where command.key == key { finish(id) }
    }
    func dismiss(_ notice: Notice) {
        guard notice.dismissible else { return }
        sendCommand("dismiss", notice: notice)
    }
    func open(_ notice: Notice) {
        guard notice.openable == true else { return }
        sendCommand("open", notice: notice)
    }
    func beginReply(_ notice: Notice, action: NoticeAction) {
        guard action.enabled, action.input else { return }
        if replyTarget?.key != notice.key { replyDraft = "" }
        replyTarget = ReplyTarget(key: notice.key, action: action.id)
    }
    func perform(_ notice: Notice, action: NoticeAction, text: String? = nil) {
        guard action.enabled else { return }
        if action.input {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf16.count <= 4000, action.freeform || action.choices.contains(text) else {
                beginReply(notice, action: action); return
            }
        }
        sendCommand("action", notice: notice, action: action.id, text: text, capabilityRevision: action.revision)
    }
    @discardableResult
    func seek(_ notice: Notice, action: NoticeAction, position: Int64) -> Bool {
        guard notice.isMedia, action.enabled, action.mediaControl == "seek", position >= 0 else { return false }
        return sendCommand("action", notice: notice, action: action.id, capabilityRevision: action.revision, position: position)
    }
    func receiveResult(id: String, status: String) -> Removal? {
        guard let command = pending[id] else { return nil }
        if status == "sent", command.kind != "dismiss" {
            if replyTarget?.key == command.key { replyTarget = nil; replyDraft = "" }
            finish(id)
        } else if status == "removed", command.kind == "dismiss" {
            finish(id)
            return Removal(key: command.key, revision: command.revision)
        } else {
            let text = failureMessage(status, kind: command.kind)
            feedback[command.key] = text; finish(id, error: text)
        }
        return nil
    }
    @discardableResult
    private func sendCommand(_ kind: String, notice: Notice, action: String? = nil, text: String? = nil,
                             capabilityRevision: String? = nil, position: Int64? = nil) -> Bool {
        guard connected(), !pendingKeys.contains(notice.key), let latest = current(notice.key) else { return false }
        if let capabilityRevision {
            guard kind == "action", notice.isMedia, latest.isMedia,
                  latest.actions?.contains(where: { $0.id == action && $0.revision == capabilityRevision && $0.enabled }) == true else { return false }
        } else if latest.revision != notice.revision { return false }
        let id = UUID().uuidString
        var message = Message(kind)
        message.key = notice.key; message.revision = capabilityRevision ?? notice.revision; message.command = id
        message.action = action; message.text = text; message.position = position
        message.sentAt = Int64(Date().timeIntervalSince1970 * 1000); message.expiresAt = message.sentAt! + 8000
        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.finish(id, error: kind == "dismiss" ? "Dismissal not confirmed" : "Phone action not confirmed")
        }
        let feedbackTimer = Timer.scheduledTimer(withTimeInterval: Self.feedbackDelay, repeats: false) { [weak self] _ in
            guard let self, self.pending[id] != nil else { return }
            self.busyKeys.insert(notice.key)
        }
        pending[id] = Pending(key: notice.key, revision: notice.revision, kind: kind, timer: timer, feedbackTimer: feedbackTimer)
        pendingKeys.insert(notice.key); clearFeedback(notice.key)
        if error != nil { error = nil }
        send(message)
        return true
    }
    private func finish(_ id: String, error: String? = nil) {
        guard let command = pending.removeValue(forKey: id) else { return }
        command.timer.invalidate(); command.feedbackTimer.invalidate()
        pendingKeys.remove(command.key)
        if busyKeys.contains(command.key) { busyKeys.remove(command.key) }
        if let error { self.error = error; feedback[command.key] = error }
    }
    private func clearFeedback(_ key: String) {
        guard let previous = feedback[key] else { return }
        feedback.removeValue(forKey: key)
        if error == previous { error = nil }
    }
    private func failureMessage(_ status: String, kind: String) -> String {
        switch status {
        case "changed": return "Notification changed"
        case "blocked": return "Cannot dismiss this notification"
        case "expired": return "Command expired · try again"
        case "requires_unlock": return "Unlock your phone first"
        case "gone": return "Notification no longer active"
        case "unavailable": return "Action no longer available"
        case "unsupported_input": return "Complete this action on your phone"
        case "access_denied": return "Phone notification access denied"
        case "failed": return "Phone action failed"
        default: return kind == "dismiss" ? "Dismissal not confirmed" : "Phone action not confirmed"
        }
    }
}

import Foundation
import Combine
import PhoneCheckCore

/// Owns in-flight commands and transient UI feedback. It never retains notification history.
final class NotificationCommandController: ObservableObject {
    struct ReplyTarget: Equatable { var key: String; var action: String }
    struct Removal { var key: String; var revision: String }
    private struct Pending { var key: String; var revision: String; var kind: String; var timer: Timer }
    @Published private(set) var pendingKeys: Set<String> = []
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
        pending.values.forEach { $0.timer.invalidate() }; pending = [:]
        pendingKeys = []; feedback = [:]; error = nil; replyTarget = nil; replyDraft = ""
    }
    func notificationChanged(_ notice: Notice) {
        if feedback[notice.key] == error { error = nil }
        feedback.removeValue(forKey: notice.key)
        for (id, command) in Array(pending) where command.kind == "dismiss" && command.key == notice.key && command.revision != notice.revision {
            finish(id, error: "Notification changed")
        }
        if let target = replyTarget, target.key == notice.key, notice.actions?.contains(where: { $0.id == target.action }) != true {
            replyTarget = nil // Keep the draft for an explicit retry on the updated notification.
        }
    }
    func notificationRemoved(_ key: String) {
        if feedback[key] == error { error = nil }
        feedback.removeValue(forKey: key)
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
        sendCommand("action", notice: notice, action: action.id, text: text)
    }
    func receiveResult(id: String, status: String) -> Removal? {
        guard let command = pending[id] else { return nil }
        if status == "sent", command.kind != "dismiss" {
            feedback[command.key] = "Sent to phone"
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
    private func sendCommand(_ kind: String, notice: Notice, action: String? = nil, text: String? = nil) {
        guard connected(), !pendingKeys.contains(notice.key), current(notice.key)?.revision == notice.revision else { return }
        let id = UUID().uuidString
        var message = Message(kind)
        message.key = notice.key; message.revision = notice.revision; message.command = id
        message.action = action; message.text = text
        message.sentAt = Int64(Date().timeIntervalSince1970 * 1000); message.expiresAt = message.sentAt! + 8000
        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.finish(id, error: kind == "dismiss" ? "Dismissal not confirmed" : "Phone action not confirmed")
        }
        pending[id] = Pending(key: notice.key, revision: notice.revision, kind: kind, timer: timer)
        pendingKeys.insert(notice.key); feedback.removeValue(forKey: notice.key); error = nil
        send(message)
    }
    private func finish(_ id: String, error: String? = nil) {
        guard let command = pending.removeValue(forKey: id) else { return }
        command.timer.invalidate(); pendingKeys.remove(command.key)
        if let error { self.error = error; feedback[command.key] = error }
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

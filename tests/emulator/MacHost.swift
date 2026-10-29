import AppKit
import Foundation
import Combine
import UserNotifications
import PhoneCheckCore

// Compiled with the production Companion, Credentials, Transport, and PhoneCheckCore.
// A different bundle identifier isolates development pairing storage and OS notifications from the app.
@main
struct MacHost {
    static func main() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHONECHECK_E2E_DIR"]!)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try Credentials.clear()
        let model = Companion()
        var connectionCount = 0
        let observation = model.$connected.sink { connected in
            if connected { connectionCount += 1 }
        }
        var pairedCodeWritten = false
        var handled = ""
        var ticks = 0
        var delivered: [String] = []
        var deliveredImage = false
        var nativeButtons: [String] = []
        var nativeReply = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if !pairedCodeWritten && model.listening {
                model.beginPairing()
                if model.pairing {
                    model.host = "10.0.2.2" // Android Emulator's host-loopback alias.
                    let codeURL = directory.appendingPathComponent("pairing")
                    try! model.code.write(to: codeURL, atomically: true, encoding: .utf8)
                    try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: codeURL.path)
                    pairedCodeWritten = true
                }
            }
            if let data = try? Data(contentsOf: directory.appendingPathComponent("command.json")),
               let command = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let id = command["id"], id != handled {
                handled = id
                switch command["action"] {
                case "dismiss":
                    if let item = model.notices.first(where: { $0.title == command["title"] }) { model.commands.dismiss(item) }
                case "perform", "reply", "native":
                    if let item = model.notices.first(where: { $0.title == command["title"] }),
                       let action = item.actions?.first(where: { $0.title == command["actionTitle"] }) {
                        if command["action"] == "native" {
                            model.handleNotificationAction(NotificationAlerts.actionPrefix + action.id, key: item.key, revision: item.revision, text: command["text"])
                        } else {
                            model.commands.perform(item, action: action, text: command["text"])
                        }
                    }
                case "authorize": model.allowAlerts()
                case "open":
                    if let item = model.notices.first(where: { $0.title == command["title"] }) { model.commands.open(item) }
                case "stop":
                    model.unpair()
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent("pairing"))
                    exit(0)
                default: break
                }
            }
            ticks += 1
            if ticks % 10 == 0 {
                UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                    let own = notifications.filter { $0.request.identifier.contains("phonecheck.demo") }
                    DispatchQueue.main.async {
                        delivered = own.map { $0.request.identifier }
                        deliveredImage = own.contains { !$0.request.content.attachments.isEmpty }
                    }
                }
                UNUserNotificationCenter.current().getNotificationCategories { categories in
                    DispatchQueue.main.async {
                        nativeButtons = categories.flatMap { $0.actions.map(\.title) }
                        nativeReply = categories.contains { $0.actions.contains { $0 is UNTextInputNotificationAction } }
                    }
                }
            }
            let titles = model.notices.filter { $0.app == "Notification Fixture" }.map(\.title).sorted()
            let fixture = model.notices.filter { $0.app == "Notification Fixture" }
            let samples = model.notices.filter { $0.key.contains("phonecheck.demo") || ($0.packageName == "dev.phonecheck" && $0.kind == "call") }
            let summary = samples.map(summarize)
            let state: [String: Any] = [
                "listening": model.listening, "paired": model.paired, "connected": model.connected,
                "connections": connectionCount,
                "titles": titles, "count": fixture.count, "pending": model.commands.pendingKeys.count,
                "blocked": fixture.filter { !$0.dismissible }.count,
                "error": model.error ?? model.commands.error ?? "", "handled": handled,
                "samples": summary, "feedback": model.commands.feedback,
                "alertsAllowed": model.alertsAllowed, "delivered": delivered, "deliveredImage": deliveredImage,
                "nativeButtons": nativeButtons, "nativeReply": nativeReply,
                "snapshotBytes": samples.reduce(0) { $0 + ((try? JSONEncoder().encode($1).count) ?? 0) },
                "appIconPresent": Bundle.main.url(forResource: "PhoneCheck", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } != nil
            ]
            let data = try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
            try! data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }
        withExtendedLifetime((model, timer, observation)) { app.run() }
    }
}

private func summarize(_ item: Notice) -> [String: Any] {
    var row: [String: Any] = [:]
    row["title"] = item.title; row["kind"] = item.kind ?? "basic"
    row["key"] = item.key; row["revision"] = item.revision
    row["bodyLength"] = item.body.utf16.count
    row["lineCount"] = item.lines?.count ?? 0; row["messageCount"] = item.messages?.count ?? 0
    row["hasImage"] = NoticeImage.image(item) != nil; row["hasIcon"] = NoticeImage.icon(item) != nil
    row["progress"] = item.progress?.value ?? -1; row["indeterminate"] = item.progress?.indeterminate ?? false
    row["grouped"] = item.groupKey != nil; row["summary"] = item.groupSummary == true
    row["openable"] = item.openable == true; row["dismissible"] = item.dismissible
    row["actions"] = item.actions?.map(\.title) ?? []
    row["disabledActions"] = item.actions?.filter { !$0.enabled }.count ?? 0
    row["replyActions"] = item.actions?.filter { $0.input && $0.enabled }.count ?? 0
    return row
}

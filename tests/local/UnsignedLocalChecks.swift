import AppKit
import Foundation
import Network
import PhoneCheckCore

/// Packaged under an isolated identity, without cloud configuration or a Google session.
@main
struct UnsignedLocalChecks {
    static func wait(_ label: String, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(8)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(condition(), label)
    }
    private final class FixtureConnection: NotificationConnection {
        var onMessage: ((Message) -> Void)?
        var onClose: (() -> Void)?
        var closed = false
        func start() {
            var status = Message("device_status"); status.battery = BatteryStatus(percentage: 73, charging: true)
            onMessage?(status)
            var snapshot = Message("snapshot"); snapshot.items = []
            onMessage?(snapshot)
        }
        func send(_ message: Message) {}
        func close() {
            guard !closed else { return }
            closed = true
            let callback = onClose; onClose = nil; onMessage = nil; callback?()
        }
    }
    static func lifecycleChecks() throws {
        try Credentials(secret: Wire.random(), peer: UUID().uuidString.lowercased()).save()
        let model = Companion(localPort: 47833)
        precondition(model.paired && model.backgroundSyncActive)
        let first = FixtureConnection()
        model.connect(using: first)
        precondition(model.connected && model.connectionRoute == .local && model.battery?.percentage == 73)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        precondition(first.closed && !model.backgroundSyncActive && !model.connected && !model.listening)
        precondition(model.connectionRoute == nil && model.battery == nil)
        let asleep = FixtureConnection()
        model.connect(using: asleep)
        precondition(asleep.closed && !model.connected)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(model.backgroundSyncActive && model.paired)
        let next = FixtureConnection()
        model.connect(using: next)
        precondition(model.connected && model.connectionRoute == .local)
        model.unpair()
        precondition(next.closed && !model.connected && !model.backgroundSyncActive && model.connectionRoute == nil)
        print("Mac background activity, sleep pause, sleeping-connection rejection, wake, route state and unpair passed (simulated transport)")
    }
    static func main() throws {
        _ = NSApplication.shared
        precondition(!CloudAccount.shared.signedIn)
        try Credentials.clear()
        defer { try? Credentials.clear() }
        if CommandLine.arguments.contains("--lifecycle-only") { try lifecycleChecks(); return }
        let port: UInt16 = 47833
        let occupied = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        occupied.start(queue: .main)
        wait("Port occupied for retry test") { occupied.state == .ready }
        let model = Companion(localPort: port)
        wait("Port conflict detected") { model.error != nil }
        occupied.cancel()
        wait("Signed-out listener starts") { model.listening }
        model.beginPairing()
        precondition(model.pairing && model.code.hasPrefix("pc1|"))
        let credentials = try Credentials.load()!
        precondition(credentials.ownerUID == nil && credentials.pairID == nil)
        let peer = UUID().uuidString.lowercased()
        let item = Notice(key: "local-check", app: "Local Check", title: "Local notification", body: "Synthetic",
                          revision: String(repeating: "a", count: 64), dismissible: true, postedAt: 1)

        func connect(secret: Data) -> FramedConnection {
            let client = FramedConnection(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp))
            let nonce = Wire.random()
            var material = Data()
            client.onMessage = { message in
                switch message.type {
                case "challenge":
                    material = Wire.material(Data(base64Encoded: message.nonce!)!, nonce, peer)
                    var auth = Message("authenticate"); auth.peer = peer
                    auth.nonce = nonce.base64EncodedString()
                    auth.proof = Wire.derive(secret, label: "client-proof", material: material).base64EncodedString()
                    client.send(auth)
                case "ready":
                    precondition(Wire.verify(Data(base64Encoded: message.proof!)!, secret: secret, label: "server-proof", material: material))
                    client.incoming = Cipher(key: Wire.derive(secret, label: "s2c", material: material))
                    client.outgoing = Cipher(key: Wire.derive(secret, label: "c2s", material: material))
                    var info = Message("device_info"); info.deviceName = "Local fixture"; client.send(info)
                    var status = Message("device_status"); status.battery = BatteryStatus(percentage: 73, charging: true)
                    client.send(status)
                    client.send(Message("snapshot_begin"))
                    var items = Message("snapshot_items"); items.items = [item]; client.send(items)
                    client.send(Message("snapshot_end"))
                case "ping": client.send(Message("pong"))
                case "dismiss":
                    precondition(message.key == item.key && message.revision == item.revision)
                    var result = Message("result"); result.command = message.command; result.status = "removed"
                    client.send(result)
                default: preconditionFailure("Unexpected message")
                }
            }
            client.start()
            return client
        }
        let rejected = connect(secret: Wire.random())
        var refused = false
        rejected.onClose = { refused = true }
        wait("Unknown secret refused") { refused }
        precondition(!model.paired && !model.connected)

        let first = connect(secret: credentials.secret)
        wait("Signed-out snapshot and battery") { model.connected && model.notices.count == 1 && model.battery?.percentage == 73 }
        precondition(model.connectionRoute == .local && model.backgroundSyncActive)
        let persisted = try Credentials.load()!
        precondition(persisted.peer == peer && persisted.ownerUID == nil && persisted.pairID == nil)
        model.commands.dismiss(model.notices[0])
        wait("Local command and confirmation") { model.notices.isEmpty && model.commands.pendingKeys.isEmpty }
        first.close()
        wait("Local disconnect") { !model.connected }
        precondition(model.connectionRoute == nil)
        // Exercise the same callbacks as real workspace sleep/wake without sleeping the host.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        precondition(!model.backgroundSyncActive && !model.connected)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        wait("Listener resumes after wake") { model.listening && model.backgroundSyncActive }
        let second = connect(secret: credentials.secret)
        wait("Fresh local reconnect snapshot") { model.connected && model.notices.count == 1 }
        precondition(!CloudAccount.shared.signedIn)
        model.unpair()
        wait("Local unpair closes link") { !model.connected && !model.paired }
        let cleared = try Credentials.load()
        precondition(cleared == nil && !model.backgroundSyncActive && model.connectionRoute == nil)
        second.close()
        print("Signed-out pairing, port recovery, encrypted sync, battery, commands, route status, sleep/wake, reconnect and unpair passed")
    }
}

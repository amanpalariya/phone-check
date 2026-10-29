import AppKit
import SwiftUI
import Network
import UserNotifications
import PhoneCheckCore

final class Companion: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var status = "Not paired"
    @Published private(set) var notices: [Notice] = []
    var notificationCount: Int { NotificationSection.count(notices) }
    @Published private(set) var phoneName: String?
    var phoneIdentifier: String? { credentials?.peer }
    @Published private(set) var paired = false
    @Published private(set) var connected = false
    @Published private(set) var listening = false
    @Published private(set) var pairing = false
    @Published private(set) var addresses: [String] = []
    @Published var host = ""
    @Published private(set) var alertsAllowed = false
    @Published private(set) var error: String?
    private var credentials: Credentials?
    private var listener: NWListener?
    private var candidates: [UUID: FramedConnection] = [:]
    private var active: (any NotificationConnection)?
    private var usesLocalNetwork = true
    private var state = ActiveState()
    private var phoneAttention = PhoneAttentionState()
    private var staged: [Notice]?
    private var stagedBytes = 0
    private var pairExpiry: Date?
    private var heartbeat: Timer?
    private var pairingTimer: Timer?
    private var syncDeadline: Timer?
    private let center = UNUserNotificationCenter.current()
    private lazy var alerts = NotificationAlerts(center: center)
    private(set) lazy var commands = NotificationCommandController(
        current: { [weak self] key in self?.state.items[key] },
        connected: { [weak self] in self?.connected == true },
        send: { [weak self] message in self?.active?.send(message) })

    init(startServices: Bool = true) {
        super.init()
        guard startServices else { return }
        center.delegate = self
        alerts.register([])
        // Clearing or timing out a Mac alert never dismisses it on the phone.
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        do {
            credentials = try Credentials.load()
            phoneName = credentials?.phoneName
            paired = credentials?.peer != nil
            status = paired ? "Disconnected" : "Not paired"
        } catch { self.error = "Pairing storage unavailable" }
        refreshAuthorization()
        startListening()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.active?.send(Message("ping"))
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    #if PHONECHECK_VISUAL_TEST
    func showPreview(_ items: [Notice]) {
        notices = items; paired = true; connected = true; listening = true
        alertsAllowed = true; status = "Connected"
    }
    #endif
    var code: String {
        guard pairing, let credentials, !host.isEmpty else { return "" }
        let secret = credentials.secret.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "pc1|\(host)|\(Wire.port)|\(secret)"
    }
    func startListening() {
        guard usesLocalNetwork, listener == nil else { return }
        addresses = privateAddresses()
        if !addresses.contains(host) { host = addresses.first ?? "" }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Wire.port)!)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                guard let self, self.listener === listener else { return }
                switch newState {
                case .ready: self.listening = true
                case .failed:
                    self.listening = false; self.error = "Local connection unavailable"
                    self.listener?.cancel(); self.listener = nil
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: .main)
        } catch { self.error = "Port unavailable" }
    }
    func beginPairing() {
        guard !paired, listening else { return }
        addresses = privateAddresses()
        if !addresses.contains(host) { host = addresses.first ?? "" }
        guard !addresses.isEmpty else { error = "Connect to Wi-Fi"; return }
        do {
            let next = Credentials(secret: Wire.random(), peer: nil)
            try next.save(); credentials = next
            pairing = true; error = nil; pairExpiry = Date().addingTimeInterval(300)
            pairingTimer?.invalidate()
            pairingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in self?.cancelPairing() }
        } catch { self.error = "Could not save pairing" }
    }
    func cancelPairing() {
        pairing = false; pairExpiry = nil; pairingTimer?.invalidate()
        if !paired {
            credentials = nil
            do { try Credentials.clear() } catch { self.error = "Could not clear pairing" }
            Array(candidates.values).forEach { $0.close() }
        }
    }
    func unpair() {
        do { try Credentials.clear() } catch { self.error = "Could not clear pairing"; return }
        credentials = nil; phoneName = nil; paired = false; pairing = false; pairExpiry = nil
        pairingTimer?.invalidate()
        active?.close(); Array(candidates.values).forEach { $0.close() }
        clearActive(); status = "Not paired"; error = nil
        usesLocalNetwork = true; startListening()
    }
    private func accept(_ connection: NWConnection) {
        guard candidates.count < 4, let credentials,
              credentials.peer != nil || (pairing && (pairExpiry ?? .distantPast) > Date()) else { connection.cancel(); return }
        let id = UUID(), serverNonce = Wire.random()
        let client = FramedConnection(connection)
        candidates[id] = client
        var authenticated = false
        client.onClose = { [weak self, weak client] in
            guard let self else { return }
            self.candidates.removeValue(forKey: id)
            if let client, self.active === client {
                self.active = nil; self.clearActive(); self.status = self.paired ? "Disconnected" : "Not paired"
            }
        }
        client.onMessage = { [weak self, weak client] message in
            guard let self, let client else { return }
            if authenticated {
                guard self.active === client else { client.close(); return }
                self.receive(message); return
            }
            guard message.type == "authenticate", let peer = message.peer,
                  peer.count == 36, UUID(uuidString: peer) != nil,
                  let nonce = message.nonce.flatMap({ Data(base64Encoded: $0) }), nonce.count == 32,
                  let proof = message.proof.flatMap({ Data(base64Encoded: $0) }), proof.count == 32,
                  let current = self.credentials, current.secret == credentials.secret,
                  (current.peer == peer || (current.peer == nil && self.pairing && (self.pairExpiry ?? .distantPast) > Date())) else { client.close(); return }
            let material = Wire.material(serverNonce, nonce, peer)
            guard Wire.verify(proof, secret: current.secret, label: "client-proof", material: material) else { client.close(); return }
            do {
                var saved = current; saved.peer = peer
                try saved.save(); self.credentials = saved
            } catch { self.error = "Could not save pairing"; client.close(); return }
            self.active?.close(); self.clearActive()
            self.active = client; authenticated = true
            self.paired = true; self.pairing = false; self.pairExpiry = nil; self.pairingTimer?.invalidate()
            self.status = "Syncing…"; self.error = nil
            var ready = Message("ready")
            ready.proof = Wire.derive(current.secret, label: "server-proof", material: material).base64EncodedString()
            client.send(ready)
            client.incoming = Cipher(key: Wire.derive(current.secret, label: "c2s", material: material))
            client.outgoing = Cipher(key: Wire.derive(current.secret, label: "s2c", material: material))
            self.syncDeadline = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak client] _ in client?.close() }
        }
        client.start()
        var challenge = Message("challenge"); challenge.nonce = serverNonce.base64EncodedString()
        client.send(challenge)
    }
    /// Cloud provisioning supplies an authenticated session after explicit pairing.
    /// The same snapshot, validation, commands and alert policy serve every transport.
    func connect(using connection: any NotificationConnection) {
        guard paired else { connection.close(); error = "Pair a phone first"; return }
        usesLocalNetwork = false
        listener?.cancel(); listener = nil; listening = false
        active?.close(); Array(candidates.values).forEach { $0.close() }
        clearActive(); active = connection; status = "Syncing…"
        connection.onMessage = { [weak self, weak connection] message in
            guard let self, let connection, self.active === connection else { return }
            self.receive(message)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection, self.active === connection else { return }
            self.active = nil; self.clearActive(); self.status = "Disconnected"
        }
        syncDeadline = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak connection] _ in connection?.close() }
        connection.start()
    }

    private func receive(_ message: Message) {
        switch message.type {
        case "device_info":
            // Only accept device identity inside the authenticated encrypted session.
            guard let name = message.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name.count <= 128,
                  name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                  var saved = credentials, saved.peer != nil, saved.phoneName != name else { return }
            saved.phoneName = name
            do {
                try saved.save(); credentials = saved; phoneName = name
            } catch { self.error = "Could not save phone name" }
        case "snapshot_begin":
            guard !state.synchronized, staged == nil else { active?.close(); return }
            staged = []; stagedBytes = 0
        case "snapshot_items":
            guard staged != nil, let batch = message.items, batch.allSatisfy(validNotice),
                  staged!.count + batch.count <= 1000 else { active?.close(); return }
            stagedBytes += (try? Wire.json(message).count) ?? Wire.maxFrame
            guard stagedBytes <= 32 * 1024 * 1024 else { active?.close(); return }
            staged!.append(contentsOf: batch)
        case "snapshot_end":
            guard let items = staged else { active?.close(); return }
            completeSnapshot(items)
        case "snapshot":
            guard !state.synchronized, staged == nil, let items = message.items, items.count <= 1000,
                  items.allSatisfy(validNotice) else { active?.close(); return }
            completeSnapshot(items)
        case "attention":
            updateAttention(message)
            if phoneAttention.inUse == true { center.removeAllPendingNotificationRequests() }
        case "upsert":
            updateAttention(message)
            guard state.synchronized, let item = message.item, validNotice(item),
                  state.items.count < 1000 || state.items[item.key] != nil else { active?.close(); return }
            let previous = state.items[item.key]
            if state.upsert(item) {
                let contentChanged = previous?.revision != item.revision
                if contentChanged { commands.notificationChanged(item) }
                publish()
                if alertsAllowed && contentChanged && item.groupSummary != true && AlertPolicy.shouldAlert(
                    phoneInUse: phoneAttention.inUse ?? message.phoneInUse, sentAt: message.sentAt,
                    now: Int64(Date().timeIntervalSince1970 * 1000)) {
                    alerts.deliver(item, isNew: previous == nil) { [weak self] in self?.error = "Mac notification unavailable" }
                }
            }
        case "remove":
            guard state.synchronized, let key = message.key else { active?.close(); return }
            _ = state.remove(key); removeAlert(key); commands.notificationRemoved(key)
            publish()
        case "result":
            guard let id = message.command, let status = message.status else { return }
            if let removal = commands.receiveResult(id: id, status: status) {
                if state.remove(removal.key, revision: removal.revision) { removeAlert(removal.key) }
                publish()
            }
        case "pong": break
        default: active?.close()
        }
    }
    private func updateAttention(_ message: Message) {
        phoneAttention.update(inUse: message.phoneInUse, sentAt: message.sentAt,
                              now: Int64(Date().timeIntervalSince1970 * 1000))
    }
    private func completeSnapshot(_ items: [Notice]) {
        state.snapshot(items); staged = nil; stagedBytes = 0
        syncDeadline?.invalidate(); syncDeadline = nil
        connected = true; status = "Connected"; publish()
    }
    private func validNotice(_ item: Notice) -> Bool {
        guard !item.key.isEmpty, item.key.utf8.count <= 4096, item.app.count <= 256, item.title.count <= 2048,
              item.body.count <= 8192, item.revision.count == 64,
              (item.image?.count ?? 0) <= 44000, (item.appIcon?.count ?? 0) <= 16400, (item.groupKey?.count ?? 0) <= 4096,
              (item.actions?.count ?? 0) <= 6, (item.lines?.count ?? 0) <= 20,
              (item.messages?.count ?? 0) <= 12 else { return false }
        if let lines = item.lines, !lines.allSatisfy({ $0.count <= 1024 }) { return false }
        if let messages = item.messages, !messages.allSatisfy({ $0.sender.count <= 256 && $0.text.count <= 2048 }) { return false }
        if let progress = item.progress, progress.max < 0 || progress.value < 0 || progress.value > max(1, progress.max) { return false }
        if let actions = item.actions {
            guard Set(actions.map(\.id)).count == actions.count else { return false }
            return actions.allSatisfy { !$0.id.isEmpty && $0.id.count <= 64 && $0.title.count <= 128 &&
                $0.choices.count <= 8 && $0.choices.allSatisfy { $0.count <= 256 } }
        }
        return true
    }
    private func publish() {
        notices = state.items.values.sorted {
            $0.postedAt == $1.postedAt ? $0.key < $1.key : $0.postedAt > $1.postedAt
        }
        // Android summaries repeat their children's content. They remain active
        // for group capabilities, but must not leave a second native Mac alert.
        for notice in notices where notice.groupSummary == true { removeAlert(notice.key) }
        alerts.register(notices)
    }
    private func clearActive() {
        connected = false; state.reset(); phoneAttention = PhoneAttentionState()
        notices = []; staged = nil; stagedBytes = 0
        commands.reset(); alerts.register([])
        syncDeadline?.invalidate(); syncDeadline = nil
        center.removeAllDeliveredNotifications(); center.removeAllPendingNotificationRequests()
    }
    private func removeAlert(_ key: String) {
        center.removeDeliveredNotifications(withIdentifiers: [key])
        center.removePendingNotificationRequests(withIdentifiers: [key])
    }
    func refreshAuthorization() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async { self?.alertsAllowed = settings.authorizationStatus == .authorized }
        }
    }
    func allowAlerts() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .denied {
                DispatchQueue.main.async { self.openNotificationSettings() }
            } else {
                self.center.requestAuthorization(options: [.alert]) { [weak self] allowed, _ in
                    DispatchQueue.main.async { self?.alertsAllowed = allowed }
                }
            }
        }
    }
    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async { [weak self] in
            completionHandler(self?.phoneAttention.inUse == true ? [] : [.banner, .list])
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            defer { completionHandler() }
            guard let key = response.notification.request.content.userInfo["key"] as? String,
                  let revision = response.notification.request.content.userInfo["revision"] as? String else { return }
            self?.handleNotificationAction(response.actionIdentifier, key: key, revision: revision,
                text: (response as? UNTextInputNotificationResponse)?.userText)
        }
    }
    /// Shared by native banner responses and the integration harness.
    func handleNotificationAction(_ identifier: String, key: String, revision: String, text: String? = nil) {
        guard let item = state.items[key], item.revision == revision else {
            error = "Notification changed or is no longer active"
            NotificationCenter.default.post(name: .init("PhoneCheckShow"), object: nil)
            return
        }
        switch identifier {
        case NotificationAlerts.dismiss: commands.dismiss(item)
        case NotificationAlerts.open: commands.open(item)
        case UNNotificationDefaultActionIdentifier:
            NotificationCenter.default.post(name: .init("PhoneCheckShow"), object: nil)
        default:
            let prefix = NotificationAlerts.actionPrefix
            guard identifier.hasPrefix(prefix),
                  let action = item.actions?.first(where: { $0.id == String(identifier.dropFirst(prefix.count)) }) else { return }
            if action.input && text == nil {
                commands.beginReply(item, action: action)
                NotificationCenter.default.post(name: .init("PhoneCheckShow"), object: nil)
            } else { commands.perform(item, action: action, text: text) }
        }
    }
    @objc private func willSleep() {
        active?.close(); Array(candidates.values).forEach { $0.close() }
        cancelPairing()
    }
    @objc private func didWake() { startListening(); refreshAuthorization() }
}

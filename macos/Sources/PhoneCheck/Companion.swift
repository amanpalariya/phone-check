import AppKit
import SwiftUI
import Network
import UserNotifications
import PhoneCheckCore

enum ConnectionRoute { case local, cloud }

final class Companion: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var status = "Not paired"
    @Published private(set) var notices: [Notice] = []
    var notificationCount: Int { NotificationSection.count(notices) }
    @Published private(set) var battery: BatteryStatus?
    @Published private(set) var phoneName: String?
    var phoneIdentifier: String? { credentials?.peer }
    @Published private(set) var paired = false
    @Published private(set) var connected = false
    @Published private(set) var connectionRoute: ConnectionRoute?
    @Published private(set) var backgroundSyncActive = false
    @Published private(set) var listening = false
    @Published private(set) var pairing = false
    @Published private(set) var addresses: [String] = []
    @Published var host = ""
    @Published private(set) var alertsAllowed = false
    @Published private(set) var error: String?
    private var credentials: Credentials?
    private let localPort: UInt16
    private var listener: NWListener?
    private var candidates: [UUID: FramedConnection] = [:]
    private var active: (any NotificationConnection)?
    private var usesLocalNetwork = false
    private var cloud: CloudSync?
    private var cloudPausedForLocal = false
    private var sleeping = false
    private var advertisedAddresses: [String]?
    private var state = ActiveState()
    private var phoneAttention = PhoneAttentionState()
    private var staged: [Notice]?
    private var stagedBytes = 0
    @Published private(set) var pairingExpiresAt: Date?
    private var backgroundActivity: NSObjectProtocol?
    private var listenerRetry: Timer?
    private var heartbeat: Timer?
    private var pairingTimer: Timer?
    private var syncDeadline: Timer?
    private let center = UNUserNotificationCenter.current()
    private lazy var alerts = NotificationAlerts(center: center)
    private(set) lazy var commands = NotificationCommandController(
        current: { [weak self] key in self?.state.items[key] },
        connected: { [weak self] in self?.connected == true },
        send: { [weak self] message in self?.active?.send(message) })

    init(startServices: Bool = true, localNetworkForTesting: Bool = false, localPort: UInt16 = Wire.port) {
        self.localPort = localPort
        usesLocalNetwork = localNetworkForTesting
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
        if localNetworkForTesting { startListening() }
        else {
            CloudAccount.shared.onChange = { [weak self] in self?.accountChanged() }
            accountChanged()
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, !self.sleeping else { return }
            self.active?.send(Message("ping"))
            self.advertiseLocalEndpoint()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    #if PHONECHECK_VISUAL_TEST
    func showPairingPreview(active: Bool = true) {
        listening = true
        guard active else { return }
        host = "192.168.1.10"
        addresses = [host, "10.0.0.2"]
        credentials = Credentials(secret: Data(repeating: 7, count: 32), peer: nil)
        pairing = true
        pairingExpiresAt = Date().addingTimeInterval(299)
    }
    func showPreview(_ items: [Notice], battery: BatteryStatus? = nil) {
        self.battery = battery
        notices = items; paired = true; connected = true; listening = true
        alertsAllowed = true; status = "Connected"
    }
    #endif
    var code: String {
        guard pairing, let credentials else { return "" }
        let secret = credentials.secret.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        if let owner = credentials.ownerUID, let pairID = credentials.pairID,
           case let project = CloudAccount.shared.projectID, !project.isEmpty {
            return "pc2|\(project)|\(owner)|\(pairID)|\(secret)"
        }
        return "pc1|\(host)|\(localPort)|\(secret)"
    }
    private func accountChanged() {
        defer { updateBackgroundActivity() }
        // A local pair remains local when the user later signs in. Upgrading requires pairing again.
        if let credentials, credentials.ownerUID == nil {
            usesLocalNetwork = true
            if active == nil { startLocalListener() }
            return
        }
        usesLocalNetwork = credentials == nil && !CloudAccount.shared.signedIn
        if usesLocalNetwork {
            status = "Not paired"
            startLocalListener()
        } else { startCloud() }
    }
    func startListening() {
        if usesLocalNetwork { startLocalListener() } else { startCloud() }
    }
    private func startLocalListener() {
        guard !sleeping, listener == nil else { return }
        listenerRetry?.invalidate(); listenerRetry = nil
        addresses = privateAddresses()
        if !addresses.contains(host) { host = addresses.first ?? "" }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: localPort)!)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                guard let self, self.listener === listener else { return }
                switch newState {
                case .ready:
                    if self.error == "Local connection unavailable" || self.error == "Port unavailable" { self.error = nil }
                    if self.usesLocalNetwork { self.listening = true }
                    self.advertiseLocalEndpoint()
                case .failed:
                    if self.usesLocalNetwork { self.listening = false; self.error = "Local connection unavailable" }
                    self.listener?.cancel(); self.listener = nil
                    self.retryLocalListener()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: .main)
        } catch { self.error = "Port unavailable"; retryLocalListener() }
    }
    private func retryLocalListener() {
        guard !sleeping, listenerRetry == nil else { return }
        listenerRetry = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.listenerRetry = nil
            self?.startLocalListener()
        }
    }
    func beginPairing() {
        defer { updateBackgroundActivity() }
        if !CloudAccount.shared.signedIn {
            usesLocalNetwork = true
            cloud?.stop(); cloud = nil
            if listener?.state == .ready { listening = true }
            else { startLocalListener() }
        }
        if !usesLocalNetwork { beginCloudPairing(); return }
        guard !paired, listening else { return }
        addresses = privateAddresses()
        if !addresses.contains(host) { host = addresses.first ?? "" }
        guard !addresses.isEmpty else { error = "Connect to Wi-Fi"; return }
        do {
            let next = Credentials(secret: Wire.random(), peer: nil)
            try next.save(); credentials = next
            pairing = true; error = nil; pairingExpiresAt = Date().addingTimeInterval(300)
            pairingTimer?.invalidate()
            pairingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.cancelPairing()
                self.error = "Pairing code expired. Try again."
            }
        } catch { self.error = "Could not save pairing" }
    }
    func cancelPairing() {
        defer { updateBackgroundActivity() }
        if !usesLocalNetwork && !paired {
            cloud?.stop(); cloud = nil
            CloudAccount.shared.root?.removeValue()
        }
        pairing = false; pairingExpiresAt = nil; pairingTimer?.invalidate()
        if !paired {
            credentials = nil
            do { try Credentials.clear() } catch { self.error = "Could not clear pairing" }
            Array(candidates.values).forEach { $0.close() }
        }
    }
    func signOut() {
        if credentials?.ownerUID == nil { CloudAccount.shared.signOut(); return }
        guard let root = CloudAccount.shared.root else { CloudAccount.shared.signOut(); return }
        root.removeValue { [weak self] failure, _ in
            guard let self else { return }
            if failure != nil { self.error = "Could not sign out. Try again."; return }
            self.clearCloudPairing(); CloudAccount.shared.signOut()
        }
    }
    func unpair() {
        defer { updateBackgroundActivity() }
        if !usesLocalNetwork, let root = CloudAccount.shared.root {
            root.removeValue { [weak self] failure, _ in
                guard let self else { return }
                if failure != nil { self.error = "Could not unpair. Try again."; return }
                self.clearCloudPairing()
            }
            return
        }
        do { try Credentials.clear() } catch { self.error = "Could not clear pairing"; return }
        credentials = nil; phoneName = nil; paired = false; pairing = false; pairingExpiresAt = nil
        pairingTimer?.invalidate()
        active?.close(); Array(candidates.values).forEach { $0.close() }
        clearActive(); status = "Not paired"; error = nil
        accountChanged()
    }
    private func clearCloudPairing() {
        defer { updateBackgroundActivity() }
        cloudPausedForLocal = false
        cloud?.stop(); cloud = nil; active?.close(); active = nil; clearActive()
        do { try Credentials.clear() } catch { self.error = "Could not clear pairing"; return }
        credentials = nil; paired = false; pairing = false; phoneName = nil
        pairingExpiresAt = nil; pairingTimer?.invalidate(); status = "Not paired"
    }
    private func startCloud() {
        defer { updateBackgroundActivity() }
        guard !sleeping, !usesLocalNetwork else { return }
        cloudPausedForLocal = false
        cloud?.stop(); cloud = nil
        let previous = active; active = nil; previous?.close(); clearActive()
        advertisedAddresses = nil
        listening = CloudAccount.shared.signedIn
        guard let uid = CloudAccount.shared.uid, let root = CloudAccount.shared.root else {
            paired = false; status = "Sign in to connect"; return
        }
        guard let saved = credentials, saved.ownerUID == uid, saved.pairID != nil else {
            paired = false; status = "Not paired"; return
        }
        paired = saved.peer != nil
        let sync = CloudSync(root: root, credentials: saved)
        sync.onPair = { [weak self] next in
            guard let self else { return false }
            do { try next.save() } catch { self.error = "Could not save pairing"; return false }
            self.credentials = next; self.paired = true; self.pairing = false
            self.updateBackgroundActivity()
            self.pairingExpiresAt = nil; self.pairingTimer?.invalidate(); self.error = nil
            return true
        }
        sync.onConnect = { [weak self] connection in
            guard let self, !self.cloudPausedForLocal else { connection.close(); return }
            self.connect(using: connection)
        }
        sync.onRevoke = { [weak self] in self?.clearCloudPairing() }
        sync.onError = { [weak self] text in self?.active?.close(); self?.error = text }
        cloud = sync; sync.start()
        startLocalListener()
    }
    private func beginCloudPairing() {
        guard !paired, let uid = CloudAccount.shared.uid, let root = CloudAccount.shared.root else { return }
        let next = Credentials(secret: Wire.random(), peer: nil, ownerUID: uid, pairID: UUID().uuidString.lowercased())
        let expiry = Date().addingTimeInterval(300)
        do { try next.save() } catch { self.error = "Could not save pairing"; return }
        cloud?.stop(); cloud = nil
        root.removeValue { [weak self] failure, _ in
            guard let self else { return }
            guard failure == nil, CloudAccount.shared.uid == uid else {
                self.error = "Could not create pairing code"; return
            }
            root.child("control/pair").setValue(["id": next.pairID!, "expiresAt": Int64(expiry.timeIntervalSince1970 * 1000)]) { [weak self] failure, _ in
                guard let self else { return }
                guard failure == nil, CloudAccount.shared.uid == uid, expiry > Date() else {
                    self.error = "Could not create pairing code"; return
                }
                self.credentials = next; self.pairing = true; self.pairingExpiresAt = expiry; self.error = nil
                self.startCloud()
                self.pairingTimer?.invalidate()
                self.pairingTimer = Timer.scheduledTimer(withTimeInterval: max(0, expiry.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                    guard let self, !self.paired else { return }
                    self.cancelPairing(); self.error = "Pairing code expired. Try again."
                }
            }
        }
    }
    private func accept(_ connection: NWConnection) {
        guard !sleeping, candidates.count < 4, let credentials,
              credentials.peer != nil || (pairing && (pairingExpiresAt ?? .distantPast) > Date()) else { connection.cancel(); return }
        let id = UUID(), serverNonce = Wire.random()
        let client = FramedConnection(connection)
        candidates[id] = client
        var authenticated = false
        client.onClose = { [weak self, weak client] in
            guard let self else { return }
            self.candidates.removeValue(forKey: id)
            if let client, self.active === client {
                self.active = nil; self.clearActive(); self.status = self.paired ? "Disconnected" : "Not paired"
                if self.cloudPausedForLocal && !self.sleeping {
                    self.cloudPausedForLocal = false
                    self.startCloud()
                }
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
                  (current.peer == peer || (current.peer == nil && self.pairing && (self.pairingExpiresAt ?? .distantPast) > Date())) else { client.close(); return }
            let material = Wire.material(serverNonce, nonce, peer)
            guard Wire.verify(proof, secret: current.secret, label: "client-proof", material: material) else { client.close(); return }
            do {
                var saved = current; saved.peer = peer
                try saved.save(); self.credentials = saved
            } catch { self.error = "Could not save pairing"; client.close(); return }
            // Detach the cloud callbacks before committing the authenticated local route.
            let previous = self.active; self.active = nil; previous?.close(); self.clearActive()
            if !self.usesLocalNetwork {
                self.cloudPausedForLocal = true
                self.cloud?.stop()
            }
            self.active = client; authenticated = true
            self.paired = true; self.pairing = false; self.pairingExpiresAt = nil; self.pairingTimer?.invalidate()
            self.status = "Syncing…"; self.error = nil
            self.updateBackgroundActivity()
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
        guard !sleeping else { connection.close(); return }
        guard paired else { connection.close(); error = "Pair a phone first"; return }
        listening = true
        advertisedAddresses = nil
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
        case "device_status":
            guard let battery = message.battery, battery.isValid else { active?.close(); return }
            self.battery = battery
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
                if alertsAllowed && contentChanged && !item.isMedia && item.groupSummary != true && AlertPolicy.shouldAlert(
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
        connected = true; connectionRoute = active is FirebaseConnection ? .cloud : .local
        status = "Connected"; error = nil; publish()
        advertiseLocalEndpoint()
    }
    /// Addresses travel inside the encrypted cloud channel, with no database schema changes.
    /// Refresh while on cloud so DHCP/interface changes are discovered without restarting.
    private func advertiseLocalEndpoint() {
        guard !usesLocalNetwork, !sleeping, connected, active is FirebaseConnection else { return }
        if listener == nil { startLocalListener() }
        guard listener?.state == .ready else { return }
        let hosts = Array(privateAddresses().prefix(8))
        guard !hosts.isEmpty, hosts != advertisedAddresses else { return }
        advertisedAddresses = hosts
        var endpoint = Message("local_endpoint"); endpoint.hosts = hosts; endpoint.port = Int(localPort)
        active?.send(endpoint)
    }
    private func validNotice(_ item: Notice) -> Bool {
        guard !item.key.isEmpty, item.key.utf8.count <= 4096, item.app.count <= 256, item.title.count <= 2048,
              item.body.count <= 8192, item.revision.count == 64,
              (item.image?.count ?? 0) <= 44000, (item.appIcon?.count ?? 0) <= 16400, (item.groupKey?.count ?? 0) <= 4096,
              (item.actions?.count ?? 0) <= (item.isMedia ? 12 : 6), (item.lines?.count ?? 0) <= 20,
              (item.messages?.count ?? 0) <= 12 else { return false }
        if let lines = item.lines, !lines.allSatisfy({ $0.count <= 1024 }) { return false }
        if let messages = item.messages, !messages.allSatisfy({ $0.sender.count <= 256 && $0.text.count <= 2048 }) { return false }
        if let progress = item.progress, progress.max < 0 || progress.value < 0 || progress.value > max(1, progress.max) { return false }
        if let media = item.media {
            guard item.isMedia, media.position >= 0, media.duration >= 0, media.updatedAt >= 0,
                  media.speed.isFinite, abs(media.speed) <= 16 else { return false }
        }
        if let actions = item.actions {
            guard Set(actions.map(\.id)).count == actions.count else { return false }
            return actions.allSatisfy { !$0.id.isEmpty && $0.id.count <= 64 && $0.title.count <= 128 && ($0.revision == nil || $0.revision?.count == 64) && ($0.icon?.count ?? 0) <= 16400 && ($0.mediaControl?.count ?? 0) <= 32 &&
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
        for notice in notices where notice.groupSummary == true || notice.isMedia { removeAlert(notice.key) }
        alerts.register(notices.filter { !$0.isMedia })
    }
    private func clearActive() {
        connected = false; connectionRoute = nil; battery = nil; state.reset(); phoneAttention = PhoneAttentionState()
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
        #if PHONECHECK_VISUAL_TEST
        return
        #else
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async { self?.alertsAllowed = settings.authorizationStatus == .authorized }
        }
        #endif
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
    /// Keep live user-requested mirroring out of App Nap without preventing system sleep.
    private func updateBackgroundActivity() {
        let needed = !sleeping && (paired || pairing) && (usesLocalNetwork || CloudAccount.shared.signedIn)
        if needed && backgroundActivity == nil {
            backgroundActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Mirror phone notifications")
        } else if !needed, let activity = backgroundActivity {
            ProcessInfo.processInfo.endActivity(activity); backgroundActivity = nil
        }
        backgroundSyncActive = backgroundActivity != nil
    }
    @objc private func willSleep() {
        sleeping = true
        updateBackgroundActivity()
        listenerRetry?.invalidate(); listenerRetry = nil
        listener?.cancel(); listener = nil; listening = false
        advertisedAddresses = nil
        active?.close(); Array(candidates.values).forEach { $0.close() }
        clearActive()
        if pairing { cancelPairing() }
        cloud?.stop()
    }
    @objc private func didWake() {
        sleeping = false
        if usesLocalNetwork { startListening() } else { startCloud() }
        updateBackgroundActivity()
        refreshAuthorization()
    }

    deinit {
        heartbeat?.invalidate(); listenerRetry?.invalidate()
        pairingTimer?.invalidate(); syncDeadline?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let activity = backgroundActivity { ProcessInfo.processInfo.endActivity(activity) }
    }
}

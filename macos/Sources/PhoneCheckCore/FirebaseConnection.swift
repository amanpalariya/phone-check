import Foundation

/// The project-specific Firebase SDK binding. Scope this client to one authorized pair/session.
/// Observe emits the current value (including nil) after connecting, then every change.
/// All callbacks are asynchronous on the main queue. Writes complete only after server acceptance.
/// Cancel must detach the listener. Never enable offline persistence for these mailboxes.
public protocol FirebaseMailbox: AnyObject {
    func observe(_ path: String, changed: @escaping (Result<String?, Error>) -> Void) -> () -> Void
    func write(_ path: String, value: String, completion: @escaping (Error?) -> Void)
    func close()
}

/// Issued only after both paired devices authorize a fresh, short-lived session.
/// Reconnecting requires a NEW random session ID, never a cached session or cipher counter.
public struct FirebaseSession {
    public let id: String
    public let secret: Data
    public let expiresAt: Int64
    public init(id: String, secret: Data, expiresAt: Int64, now: Int64) throws {
        guard UUID(uuidString: id)?.uuidString.lowercased() == id, secret.count == 32,
              expiresAt > now, expiresAt <= now + 900_000 else { throw WireError.invalid }
        self.id = id; self.secret = secret; self.expiresAt = expiresAt
    }
}

/// Two single-value mailboxes, each with an acknowledgement. Only one frame per direction
/// is in flight, so RTDB value coalescing cannot drop a snapshot chunk or a command.
/// A mailbox ACK is delivery only; phone removal still requires the normal `result` message.
public final class FirebaseConnection: NotificationConnection {
    public var onMessage: ((Message) -> Void)?
    public var onClose: (() -> Void)?
    private let mailbox: FirebaseMailbox
    private let session: FirebaseSession
    private let now: () -> Int64
    private let sendLane: String
    private let receiveLane: String
    private let outgoing: Cipher
    private let incoming: Cipher
    private var cancellations: [() -> Void] = []
    private var deadline: Timer?
    private var started = false
    private var closed = false
    private var ready = false
    private var sawInbox = false
    private var sawAck = false
    private var firstPacket: String?
    private var queue: [Data] = []
    private var queuedBytes = 0
    private var sent: Int64 = 0
    private var received: Int64 = 0
    private var pending: Int64?

    public init(mailbox: FirebaseMailbox, session: FirebaseSession, isPhone: Bool = false,
                now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.mailbox = mailbox; self.session = session; self.now = now
        sendLane = isPhone ? "phoneToMac" : "macToPhone"
        receiveLane = isPhone ? "macToPhone" : "phoneToMac"
        let material = Data(session.id.utf8)
        outgoing = Cipher(key: Wire.derive(session.secret, label: "firebase-" + sendLane, material: material))
        incoming = Cipher(key: Wire.derive(session.secret, label: "firebase-" + receiveLane, material: material))
    }
    public func start() {
        guard !started, !closed, now() < session.expiresAt else { close(); return }
        started = true; armDeadline()
        cancellations.append(mailbox.observe(receiveLane) { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .failure: self.close()
            case .success(let value):
                self.sawInbox = true
                if !self.ready { self.firstPacket = value; self.becomeReady() }
                else if let value { self.receive(value) }
            }
        })
        cancellations.append(mailbox.observe(sendLane + "Ack") { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .failure: self.close()
            case .success(let value):
                self.sawAck = true
                // Fresh session paths cannot have pre-existing outbound ACKs.
                if !self.ready, value != nil { self.close(); return }
                self.becomeReady()
                if let value { self.acknowledge(value) }
            }
        })
    }
    private func becomeReady() {
        guard !ready, sawInbox, sawAck else { return }
        ready = true
        if let firstPacket { self.firstPacket = nil; receive(firstPacket) }
        pump()
    }
    public func send(_ message: Message) {
        guard !closed else { return }
        do {
            let data = try Wire.json(message)
            guard data.count <= Wire.maxFrame - 4096, queue.count < 256,
                  queuedBytes + data.count <= 32 * 1024 * 1024 else { throw WireError.invalid }
            queue.append(data); queuedBytes += data.count; pump()
        } catch { close() }
    }
    private struct Payload: Codable {
        let session: String
        let sequence: Int64
        let expiresAt: Int64
        let message: Message
    }
    private struct Packet: Codable {
        let sequence: Int64
        let payload: String
    }
    private func pump() {
        guard ready, !closed, pending == nil, let data = queue.first else { return }
        do {
            let clock = now()
            guard clock < session.expiresAt, sent < Int64.max else { throw WireError.exhausted }
            sent += 1; pending = sent
            let payload = Payload(session: session.id, sequence: sent,
                expiresAt: min(clock + 30_000, session.expiresAt), message: try Wire.decode(data))
            let encrypted = try outgoing.seal(JSONEncoder().encode(payload))
            let packet = Packet(sequence: sent, payload: encrypted.base64EncodedString())
            let value = String(decoding: try JSONEncoder().encode(packet), as: UTF8.self)
            write(sendLane, value)
        } catch { close() }
    }
    private func receive(_ value: String) {
        do {
            guard value.utf8.count <= Wire.maxFrame * 2, now() < session.expiresAt else { throw WireError.invalid }
            let packet = try JSONDecoder().decode(Packet.self, from: Data(value.utf8))
            if packet.sequence == received, received > 0 {
                write(receiveLane + "Ack", String(received)); return
            }
            guard received < Int64.max, packet.sequence == received + 1,
                  let encrypted = Data(base64Encoded: packet.payload), encrypted.count <= Wire.maxFrame else { throw WireError.invalid }
            let data = try incoming.open(encrypted)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let clock = now()
            guard payload.session == session.id, payload.sequence == packet.sequence,
                  payload.expiresAt > clock, payload.expiresAt <= min(clock + 40_000, session.expiresAt) else { throw WireError.invalid }
            received = packet.sequence; armDeadline()
            onMessage?(payload.message)
            if !closed { write(receiveLane + "Ack", String(received)) }
        } catch { close() }
    }
    private func acknowledge(_ value: String) {
        guard let sequence = Int64(value), sequence > 0, sequence <= sent else { close(); return }
        guard sequence == pending else { return } // Repeated ACK for an earlier packet.
        pending = nil
        queuedBytes -= queue.removeFirst().count
        armDeadline(); pump()
    }
    private func write(_ path: String, _ value: String) {
        mailbox.write(path, value: value) { [weak self] error in
            if error != nil { self?.close() }
        }
    }
    private func armDeadline() {
        deadline?.invalidate()
        let seconds = min(45, Double(session.expiresAt - now()) / 1000)
        guard seconds > 0 else { close(); return }
        deadline = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.close() }
    }
    deinit {
        deadline?.invalidate(); cancellations.forEach { $0() }; mailbox.close()
    }
    public func close() {
        guard !closed else { return }
        closed = true; deadline?.invalidate(); deadline = nil
        cancellations.forEach { $0() }; cancellations = []; mailbox.close()
        queue = []; queuedBytes = 0; pending = nil; firstPacket = nil
        onMessage = nil
        let callback = onClose; onClose = nil; callback?()
    }
}

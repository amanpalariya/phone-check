import Foundation
import PhoneCheckCore

/// Deterministic, asynchronous RTDB mailbox fixture; no credentials or network.
enum FirebaseChecks {
    static let id = "00000000-0000-0000-0000-000000000001"
    static let secret = Data(0..<32)
    static func session(_ id: String = id, now: Int64 = 100_000) throws -> FirebaseSession {
        try FirebaseSession(id: id, secret: secret, expiresAt: now + 900_000, now: now)
    }
    static func run() throws {
        try orderedDeliveryAndDuplicates()
        try goldenFrame()
        try batteryDelivery()
        try localEndpointDelivery()
        try rejectsGapsTamperingExpiredAndOtherSessions()
        try boundsAndFailures()
        try configurationAndAttention()
        try streamFraming()
        try controlStream()
        try closingDuringTokenRefresh()
        print("10 Firebase/device-state check groups passed")
    }
    static func closingDuringTokenRefresh() throws {
        func wait(until condition: () -> Bool) throws {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            try expect(condition())
        }
        for stream in [false, true] {
            let gate = SuspendedTokenFixture()
            var callbacks = 0
            var mailbox: FirebaseRESTMailbox? = try FirebaseRESTMailbox(
                databaseURL: URL(string: "https://demo.firebaseio.com")!, pairID: "pair", sessionID: id,
                idToken: { await gate.wait() })
            weak var released = mailbox
            if stream { _ = mailbox!.observe("phoneToMac") { _ in callbacks += 1 } }
            else { mailbox!.write("macToPhone", value: "fixture") { _ in callbacks += 1 } }
            try wait { gate.pending == 1 }
            // Model a timeout, reconnect or session rotation while auth refresh is suspended.
            mailbox!.close(); mailbox!.close(); mailbox = nil
            gate.resume()
            try wait { released == nil }
            try expect(callbacks == 0)
        }
    }
    static func controlStream() throws {
        var parser = FirebaseControlStream()
        let events = [
            #"event: put"# + "\n" + #"data: {"path":"/","data":{"pair":{"id":"pair"}}}"# + "\n\n",
            #"event: patch"# + "\n" + #"data: {"path":"/pair","data":{"phone":"phone","proof":"proof"}}"# + "\n\n",
            #"event: patch"# + "\n" + #"data: {"path":"/","data":{"offer/id":"session"}}"# + "\n\n"
        ]
        for event in events { for byte in event.utf8 { _ = try parser.append(byte) } }
        try expect((parser.value["pair"] as? [String: Any])?["phone"] as? String == "phone")
        try expect((parser.value["offer"] as? [String: Any])?["id"] as? String == "session")
        for byte in "event: put\ndata: {\"path\":\"/pair\",\"data\":null}\n\n".utf8 { _ = try parser.append(byte) }
        try expect(parser.value["pair"] == nil)
        for event in ["auth_revoked", "cancel", "unknown"] {
            var invalid = FirebaseControlStream(), rejected = false
            do { for byte in "event: \(event)\ndata: null\n\n".utf8 { _ = try invalid.append(byte) } }
            catch { rejected = true }
            try expect(rejected)
        }
        var bounded = FirebaseControlStream(), rejected = false
        do { for byte in String(repeating: "x", count: 16_385).utf8 { _ = try bounded.append(byte) } }
        catch { rejected = true }
        try expect(rejected)
    }
    static func localEndpointDelivery() throws {
        let bus = MailboxFixture(), config = try session()
        let phone = FirebaseConnection(mailbox: bus.client(), session: config, isPhone: true, now: { 100_000 })
        let mac = FirebaseConnection(mailbox: bus.client(), session: config, now: { 100_000 })
        var received: Message?
        phone.onMessage = { received = $0 }
        phone.start(); mac.start()
        var endpoint = Message("local_endpoint")
        endpoint.hosts = ["192.168.1.2", "10.0.0.2"]; endpoint.port = Int(Wire.port)
        mac.send(endpoint); bus.drain()
        try expect(received?.type == "local_endpoint" && received?.hosts == endpoint.hosts && received?.port == 47831)
        try expect(!(bus.values["macToPhone"] ?? "").contains("192.168.1.2"))
        phone.close(); mac.close()
        try expect(bus.observers.isEmpty)
    }
    static func batteryDelivery() throws {
        let bus = MailboxFixture(), config = try session()
        let phone = FirebaseConnection(mailbox: bus.client(), session: config, isPhone: true, now: { 100_000 })
        let mac = FirebaseConnection(mailbox: bus.client(), session: config, now: { 100_000 })
        var readings: [BatteryStatus] = []
        mac.onMessage = { if let battery = $0.battery { readings.append(battery) } }
        phone.start(); mac.start()
        for battery in [BatteryStatus(percentage: 42, charging: false), BatteryStatus(percentage: 42, charging: true, powerSaving: true)] {
            var message = Message("device_status"); message.battery = battery; phone.send(message)
        }
        bus.drain()
        try expect(readings == [BatteryStatus(percentage: 42, charging: false), BatteryStatus(percentage: 42, charging: true, powerSaving: true)])
        phone.close(); mac.close()
    }
    static func goldenFrame() throws {
        let bus = MailboxFixture()
        bus.values["phoneToMac"] = #"{"sequence":1,"payload":"IANdfRKCz0knN7dsmuZAitTlw7mwUAJ5djkEWzhWBzf0wiylsdsloXutAfQl5kmu9TJXhLIeJ3wduJSkfnS4iTT4VmRYo370vU6qWTekgHwTrfse4ZHXHUrIq7zpqQUsU0wZJi1NLhreRrnXPeH5xM4UNZBZbxsbZJSlDg2J3UhENMPbO+EVQUM+i3jVqCHHnSok/KVZZjWD8RhhPUzm5g=="}"#
        let mac = FirebaseConnection(mailbox: bus.client(), session: try session(), now: { 100_000 })
        var received: Message?
        mac.onMessage = { received = $0 }; mac.start(); bus.drain()
        try expect(received?.type == "upsert" && received?.phoneInUse == true && received?.sentAt == 100_000)
        mac.close()
    }
    static func orderedDeliveryAndDuplicates() throws {
        let bus = MailboxFixture(), config = try session()
        let phone = FirebaseConnection(mailbox: bus.client(), session: config, isPhone: true, now: { 100_000 })
        let mac = FirebaseConnection(mailbox: bus.client(), session: config, now: { 100_000 })
        var received: [String] = [], commands: [String] = []
        mac.onMessage = { received.append($0.type) }; phone.onMessage = { commands.append($0.type) }
        phone.start(); mac.start()
        ["snapshot_begin", "snapshot_items", "snapshot_end", "upsert", "remove"].forEach { phone.send(Message($0)) }
        mac.send(Message("dismiss")); bus.drain()
        try expect(received == ["snapshot_begin", "snapshot_items", "snapshot_end", "upsert", "remove"])
        try expect(commands == ["dismiss"])
        // RTDB can repeat values after reconnecting its HTTP stream. Never repeat a side effect.
        bus.emit("phoneToMac", bus.values["phoneToMac"]!); bus.drain()
        try expect(received.count == 5)
        phone.close(); mac.close()
        try expect(bus.observers.isEmpty)
    }
    static func rejectsGapsTamperingExpiredAndOtherSessions() throws {
        for fault in ["gap", "tamper", "expired", "other-session"] {
            let bus = MailboxFixture(), config = try session()
            var clock: Int64 = 100_000, closes = 0, delivered = 0
            let phone = FirebaseConnection(mailbox: bus.client(), session: config, isPhone: true, now: { clock })
            phone.start(); bus.drain(); phone.send(Message("upsert")); bus.drain()
            var packet = bus.values["phoneToMac"]!
            if fault == "gap" {
                var object = try JSONSerialization.jsonObject(with: Data(packet.utf8)) as! [String: Any]
                object["sequence"] = 2
                packet = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            }
            if fault == "tamper" {
                var object = try JSONSerialization.jsonObject(with: Data(packet.utf8)) as! [String: Any]
                var bytes = Data(base64Encoded: object["payload"] as! String)!
                bytes[bytes.startIndex] ^= 1; object["payload"] = bytes.base64EncodedString()
                packet = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            }
            if fault == "expired" { clock += 31_000 }
            // A fresh backend path must not inherit any ACK or old mailbox value.
            bus.values.removeAll(); bus.values["phoneToMac"] = packet
            let receiverConfig = fault == "other-session" ? try session("00000000-0000-0000-0000-000000000002") : config
            let mac = FirebaseConnection(mailbox: bus.client(), session: receiverConfig, now: { clock })
            mac.onClose = { closes += 1 }; mac.onMessage = { _ in delivered += 1 }
            mac.start(); bus.drain(); mac.close()
            try expect(closes == 1 && delivered == 0)
            phone.close()
        }
    }
    static func boundsAndFailures() throws {
        let bus = MailboxFixture(), config = try session()
        let mac = FirebaseConnection(mailbox: bus.client(), session: config, now: { 100_000 })
        var closes = 0
        mac.onClose = { closes += 1 }
        mac.start(); bus.drain()
        for _ in 0..<257 { mac.send(Message("ping")) }
        bus.drain(); try expect(closes == 1)
        let failing = MailboxFixture(); failing.failWrites = true
        let next = FirebaseConnection(mailbox: failing.client(), session: config, now: { 100_000 })
        next.onClose = { closes += 1 }; next.start(); failing.drain()
        next.send(Message("ping")); failing.drain(); try expect(closes == 2)
        let stale = MailboxFixture(); stale.values["macToPhoneAck"] = "99"
        let rejected = FirebaseConnection(mailbox: stale.client(), session: config, now: { 100_000 })
        rejected.onClose = { closes += 1 }; rejected.start(); stale.drain(); try expect(closes == 3)
    }
    static func streamFraming() throws {
        var parser = FirebaseEventStream()
        var values: [String?] = []
        let stream = ": comment\r\nevent: keep-alive\r\ndata: null\r\n\r\n" +
            "event: put\ndata: {\n" + "data: \"path\":\"/\",\"data\":null}\n\n" +
            "event: put\ndata: {\"path\":\"/\",\"data\":\"packet\"}\n\n"
        for byte in stream.utf8 {
            if case .value(let value) = try parser.append(byte) { values.append(value) }
        }
        try expect(values.count == 2 && values[0] == nil && values[1] == "packet")
        for event in ["cancel", "auth_revoked", "patch"] {
            var invalid = FirebaseEventStream(), rejected = false
            do { for byte in "event: \(event)\ndata: null\n\n".utf8 { _ = try invalid.append(byte) } }
            catch { rejected = true }
            try expect(rejected)
        }
    }
    static func configurationAndAttention() throws {
        try expect(!AlertPolicy.shouldAlert(phoneInUse: true, sentAt: 100_000, now: 100_000))
        try expect(AlertPolicy.shouldAlert(phoneInUse: false, sentAt: 100_000, now: 100_000))
        try expect(!AlertPolicy.shouldAlert(phoneInUse: false, sentAt: 69_999, now: 100_000))
        try expect(!AlertPolicy.shouldAlert(phoneInUse: false, sentAt: 110_001, now: 100_000))
        try expect(!AlertPolicy.shouldAlert(phoneInUse: false, sentAt: nil, now: 100_000))
        try expect(AlertPolicy.shouldAlert(phoneInUse: nil, sentAt: nil, now: 100_000))
        for endpoint in ["http://demo.firebaseio.com", "https://evil.example", "https://demo.firebaseio.com/path", "https://demo.firebaseio.com?auth=secret"] {
            do {
                _ = try FirebaseRESTMailbox(databaseURL: URL(string: endpoint)!, pairID: "pair", sessionID: id, idToken: { "unused" })
                throw FixtureError.failed
            } catch FirebaseRESTError.configuration { }
        }
        var attention = PhoneAttentionState()
        attention.update(inUse: true, sentAt: 100_000, now: 100_000)
        attention.update(inUse: false, sentAt: 99_999, now: 100_000)
        try expect(attention.inUse == true)
        attention.update(inUse: false, sentAt: 100_001, now: 100_001)
        try expect(attention.inUse == false)
        attention.update(inUse: true, sentAt: 200_000, now: 100_001)
        try expect(attention.inUse == false)
        var frame = Message("upsert"); frame.phoneInUse = true; frame.sentAt = 100_000
        try expect(try Wire.decode(Wire.json(frame)).phoneInUse == true)
        let derived = Wire.derive(secret, label: "firebase-phoneToMac", material: Data(id.utf8))
        // Cross-platform vector also checked on the JVM.
        try expect(derived.map { String(format: "%02x", $0) }.joined() == "de8f5b6b7d7fbcf1c1a5c40286b5fd8b03ac56d1ce415789f495e4f7ea0863e3")
    }
}

private enum FixtureError: Error { case failed }
private func expect(_ value: @autoclosure () throws -> Bool) throws {
    guard try value() else { throw FixtureError.failed }
}
private final class MailboxFixture {
    var values: [String: String] = [:]
    var observers: [UUID: (String, (Result<String?, Error>) -> Void)] = [:]
    var jobs: [() -> Void] = []
    var failWrites = false
    func client() -> FirebaseMailbox { Client(self) }
    func drain() {
        var count = 0
        while !jobs.isEmpty {
            count += 1; precondition(count < 10_000)
            jobs.removeFirst()()
        }
    }
    func emit(_ path: String, _ value: String) {
        values[path] = value
        for (id, observer) in observers where observer.0 == path {
            jobs.append { [weak self] in self?.observers[id]?.1(.success(value)) }
        }
    }
    private final class Client: FirebaseMailbox {
        let bus: MailboxFixture
        var subscriptions: [UUID] = []
        var closed = false
        init(_ bus: MailboxFixture) { self.bus = bus }
        func observe(_ path: String, changed: @escaping (Result<String?, Error>) -> Void) -> () -> Void {
            let id = UUID(); subscriptions.append(id); bus.observers[id] = (path, changed)
            let value = bus.values[path]
            bus.jobs.append { [weak self] in self?.bus.observers[id]?.1(.success(value)) }
            return { [weak self] in self?.bus.observers.removeValue(forKey: id) }
        }
        func write(_ path: String, value: String, completion: @escaping (Error?) -> Void) {
            guard !closed else { return }
            if bus.failWrites { bus.jobs.append { completion(FixtureError.failed) }; return }
            bus.emit(path, value); bus.jobs.append { completion(nil) }
        }
        func close() {
            closed = true
            subscriptions.forEach { bus.observers.removeValue(forKey: $0) }; subscriptions = []
        }
    }
}

// A token provider that deliberately ignores cancellation until the test releases it.
private final class SuspendedTokenFixture {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<String, Never>] = []
    var pending: Int { lock.withLock { continuations.count } }
    func wait() async -> String {
        await withCheckedContinuation { continuation in lock.withLock { continuations.append(continuation) } }
    }
    func resume() {
        let pending = lock.withLock { () -> [CheckedContinuation<String, Never>] in
            let pending = continuations; continuations.removeAll(); return pending
        }
        pending.forEach { $0.resume(returning: "fixture-token") }
    }
}

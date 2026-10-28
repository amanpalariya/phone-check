import Foundation
import Network
import PhoneCheckCore

// All callbacks and state run on the main queue. Each connection has bounded frames and a deadline.
final class FramedConnection: NotificationConnection {
    let connection: NWConnection
    var onMessage: ((Message) -> Void)?
    var onClose: (() -> Void)?
    var incoming: Cipher?
    var outgoing: Cipher?
    private var closed = false
    private var deadline: Timer?
    private var queuedBytes = 0
    init(_ connection: NWConnection) { self.connection = connection }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.armTimeout(10); self.readHeader()
            case .failed, .cancelled: self.close()
            default: break
            }
        }
        connection.start(queue: .main)
    }
    func armTimeout(_ seconds: TimeInterval = 45) {
        deadline?.invalidate()
        deadline = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.close() }
    }
    func send(_ message: Message) {
        guard !closed else { return }
        do {
            let plain = try Wire.json(message)
            let data = try Wire.frame(outgoing?.seal(plain) ?? plain)
            guard queuedBytes + data.count <= Wire.maxFrame * 2 else { close(); return }
            queuedBytes += data.count
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.queuedBytes -= data.count
                if error != nil { self.close() }
            })
        } catch { close() }
    }
    private func readHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            guard error == nil, let data, data.count == 4 else { self.close(); return }
            let count = data.reduce(0) { ($0 << 8) | Int($1) }
            let limit = self.incoming == nil ? 4096 : Wire.maxFrame
            guard count > 0, count <= limit else { self.close(); return }
            self.readBody(count)
        }
    }
    private func readBody(_ count: Int) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            guard error == nil, let data, data.count == count else { self.close(); return }
            do {
                let plain = try self.incoming?.open(data) ?? data
                let message = try Wire.decode(plain)
                self.onMessage?(message)
                if self.incoming != nil { self.armTimeout() }
                if !self.closed { self.readHeader() }
            } catch { self.close() }
        }
    }
    func close() {
        guard !closed else { return }
        closed = true; deadline?.invalidate(); deadline = nil
        connection.cancel(); onMessage = nil
        let callback = onClose; onClose = nil; callback?()
    }
}

func privateAddresses() -> [String] {
    var first: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&first) == 0, let start = first else { return [] }
    defer { freeifaddrs(first) }
    var result: [String] = []
    var current: UnsafeMutablePointer<ifaddrs>? = start
    while let interface = current {
        defer { current = interface.pointee.ifa_next }
        guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
              (interface.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
        let host = String(cString: buffer)
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { continue }
        if parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])) {
            result.append(host)
        }
    }
    return Array(Set(result)).sorted()
}

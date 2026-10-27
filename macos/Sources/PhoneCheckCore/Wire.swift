import Foundation
import CryptoKit

public enum WireError: Error { case invalid, authentication, exhausted }

public struct Message: Codable {
    public var type: String
    public var nonce: String?
    public var peer: String?
    public var proof: String?
    public var items: [Notice]?
    public var item: Notice?
    public var key: String?
    public var revision: String?
    public var action: String?
    public var text: String?
    public var command: String?
    public var sentAt: Int64?
    public var expiresAt: Int64?
    public var status: String?
    public init(_ type: String) { self.type = type }
}

public enum Wire {
    public static let maxFrame = 1_048_576
    public static let port: UInt16 = 47831
    public static func random(_ count: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess)
        return Data(bytes)
    }
    public static func hmac(_ key: Data, _ value: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: value, using: SymmetricKey(data: key)))
    }
    public static func material(_ server: Data, _ client: Data, _ peer: String) -> Data {
        server + client + Data(peer.utf8)
    }
    public static func derive(_ secret: Data, label: String, material: Data) -> Data {
        hmac(secret, Data(("phonecheck-v1/" + label + "/").utf8) + material)
    }
    public static func verify(_ proof: Data, secret: Data, label: String, material: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof,
            authenticating: Data(("phonecheck-v1/" + label + "/").utf8) + material,
            using: SymmetricKey(data: secret))
    }
    public static func json(_ message: Message) throws -> Data { try JSONEncoder().encode(message) }
    public static func decode(_ data: Data) throws -> Message { try JSONDecoder().decode(Message.self, from: data) }
    public static func frame(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maxFrame else { throw WireError.invalid }
        var length = UInt32(data.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + data
    }
}

// Unique direction keys per random handshake. Implicit sequence authenticates ordering.
public final class Cipher {
    private let key: SymmetricKey
    private var sequence: UInt64 = 0
    public init(key: Data) { self.key = SymmetricKey(data: key) }
    private func nonce() throws -> AES.GCM.Nonce {
        guard sequence < UInt64.max else { throw WireError.exhausted }
        var value = sequence.bigEndian
        let bytes = Data(repeating: 0, count: 4) + withUnsafeBytes(of: &value) { Data($0) }
        return try AES.GCM.Nonce(data: bytes)
    }
    public func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: key, nonce: nonce(), authenticating: Data("phonecheck-v1".utf8))
        sequence += 1
        return box.ciphertext + box.tag
    }
    public func open(_ data: Data) throws -> Data {
        guard data.count >= 16 else { throw WireError.invalid }
        let box = try AES.GCM.SealedBox(nonce: nonce(), ciphertext: data.dropLast(16), tag: data.suffix(16))
        let plain = try AES.GCM.open(box, using: key, authenticating: Data("phonecheck-v1".utf8))
        sequence += 1
        return plain
    }
}

public struct ActiveState {
    public private(set) var items: [String: Notice] = [:]
    public private(set) var synchronized = false
    public init() {}
    public mutating func reset() { items = [:]; synchronized = false }
    public mutating func snapshot(_ notices: [Notice]) {
        items = notices.reduce(into: [:]) { $0[$1.key] = $1 }
        synchronized = true
    }
    // A snapshot reconciles silently; only live, changed posts may alert.
    public mutating func upsert(_ notice: Notice) -> Bool {
        guard synchronized else { return false }
        let changed = items[notice.key] != notice
        items[notice.key] = notice
        return changed
    }
    public mutating func remove(_ key: String, revision: String? = nil) -> Bool {
        guard let item = items[key], revision == nil || item.revision == revision else { return false }
        items.removeValue(forKey: key)
        return true
    }
}

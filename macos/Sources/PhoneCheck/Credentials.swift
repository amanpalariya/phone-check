import Foundation
#if !DEBUG
import Security
#endif

struct Credentials: Codable {
    var secret: Data
    var peer: String?
    var phoneName: String? = nil
    var ownerUID: String? = nil
    var pairID: String? = nil
    static let service = (Bundle.main.bundleIdentifier ?? "dev.phonecheck.mac") + ".pairing"
    #if DEBUG
    // Development pairing survives ad hoc re-signing without touching Keychain.
    // Never migrate production credentials: the two build configurations pair separately.
    static var developmentFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(service + ".development", isDirectory: true)
            .appendingPathComponent("pairing.json")
    }
    static func load() throws -> Credentials? {
        let file = developmentFile
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }
    func save() throws {
        let file = Self.developmentFile
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Atomic replacement and owner-only permissions, including during the write.
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func clear() throws {
        let file = developmentFile
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
    #else
    static func load() throws -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialError.unavailable }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "phone"]
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        let changes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(Self.baseQuery as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var query = Self.baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw CredentialError.unavailable }
        } else if status != errSecSuccess { throw CredentialError.unavailable }
    }
    static func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.unavailable }
    }
    #endif
}
enum CredentialError: Error { case unavailable }

import Foundation
#if !DEBUG
import Security
#endif

/// Development sessions survive ad hoc re-signing without accessing Keychain.
/// Release sessions stay in the login Keychain, separate from development files.
enum CloudTokenStore {
    struct Record: Codable {
        let uid: String
        let refreshToken: String
        var displayName: String? = nil
        var email: String? = nil
    }
    #if DEBUG
    static var developmentFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((Bundle.main.bundleIdentifier ?? "dev.phonecheck.mac") + ".firebase.development", isDirectory: true)
            .appendingPathComponent("session.json")
    }
    static func load() throws -> Record? {
        let file = developmentFile
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
    }
    static func save(_ record: Record) throws {
        let file = developmentFile
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func clear() throws {
        let file = developmentFile
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
    #else
    private static var query: [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dev.phonecheck.mac") + ".firebase",
                kSecAttrAccount as String: "session"]
    }
    static func load() throws -> Record? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw CredentialError.unavailable }
        return try JSONDecoder().decode(Record.self, from: data)
    }
    static func save(_ record: Record) throws {
        let data = try JSONEncoder().encode(record)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = query; query[kSecValueData as String] = data
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw CredentialError.unavailable }
        } else if status != errSecSuccess { throw CredentialError.unavailable }
    }
    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.unavailable }
    }
    #endif
}

import Foundation
import Security

/// Classic login Keychain for our own item: no access-group or Apple-issued signing dependency.
/// Ad hoc rebuilds can still trigger macOS's normal Keychain authorization prompt.
enum CloudTokenStore {
    struct Record: Codable { let uid: String; let refreshToken: String }
    private static var query: [String: Any] {
        #if DEBUG
        let suffix = ".development"
        #else
        let suffix = ""
        #endif
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dev.phonecheck.mac") + ".firebase" + suffix,
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
}

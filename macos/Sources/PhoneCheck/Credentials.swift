import Foundation
import Security

struct Credentials: Codable {
    var secret: Data
    var peer: String?
    var phoneName: String? = nil
    static let service = (Bundle.main.bundleIdentifier ?? "dev.phonecheck.mac") + ".pairing"
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
}
enum CredentialError: Error { case unavailable }

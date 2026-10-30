import Foundation

@main
struct CredentialStorageChecks {
    static func main() throws {
        // The runner creates a unique bundle, so checks cannot touch app pairing.
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("dev.phonecheck.credentials-checks.") == true)
        try checkCloudTokenStorage()
        let file = Credentials.developmentFile
        let directory = file.deletingLastPathComponent()
        let original = Credentials(secret: Data(repeating: 42, count: 32), peer: "test-phone", phoneName: "Test phone")
        switch CommandLine.arguments.last {
        case "write":
            precondition(tryLoad() == nil)
            try original.save()
        case "read":
            defer { try? FileManager.default.removeItem(at: directory) }
            let loaded = try Credentials.load()
            precondition(loaded?.secret == original.secret && loaded?.peer == original.peer && loaded?.phoneName == original.phoneName)
            let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
            let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as! NSNumber
            precondition(fileMode.intValue == 0o600 && directoryMode.intValue == 0o700)
            let updated = Credentials(secret: Data(repeating: 7, count: 32), peer: nil)
            try updated.save()
            precondition(tryLoad()?.secret == updated.secret && tryLoad()?.peer == nil)
            try Data("invalid".utf8).write(to: file)
            do {
                _ = try Credentials.load()
                preconditionFailure("Corrupt pairing must fail closed")
            } catch is DecodingError { }
            try Credentials.clear()
            precondition(tryLoad() == nil)
            try Credentials.clear() // Unpair is idempotent.
            // A failed save must propagate instead of silently losing pairing.
            try FileManager.default.removeItem(at: directory)
            try Data().write(to: directory)
            do {
                try original.save()
                preconditionFailure("Unwritable storage must report failure")
            } catch { }
            print("Development credential persistence, update, permissions, corruption, deletion, and write-failure checks passed")
        default: preconditionFailure("Expected write or read")
        }
    }

    private static func tryLoad() -> Credentials? {
        do { return try Credentials.load() }
        catch { preconditionFailure("Could not load development credentials") }
    }
}

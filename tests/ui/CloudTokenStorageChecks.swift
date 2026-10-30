import Foundation

func checkCloudTokenStorage() throws {
    let file = CloudTokenStore.developmentFile
    let directory = file.deletingLastPathComponent()
    let original = CloudTokenStore.Record(uid: "fixture-user", refreshToken: "fixture-refresh",
                                           displayName: "Alex Parker", email: "alex@example.com")
    switch CommandLine.arguments.last {
    case "write":
        let missing = try CloudTokenStore.load()
        precondition(missing == nil)
        try CloudTokenStore.save(original)
    case "read":
        defer { try? FileManager.default.removeItem(at: directory) }
        let restored = try CloudTokenStore.load()
        precondition(restored?.uid == original.uid && restored?.refreshToken == original.refreshToken)
        precondition(restored?.displayName == original.displayName && restored?.email == original.email)
        func checkPermissions() throws {
            let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
            let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as! NSNumber
            precondition(fileMode.intValue == 0o600 && directoryMode.intValue == 0o700)
        }
        try checkPermissions()
        // Token rotation replaces the saved session and restores restrictive permissions.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        let rotated = CloudTokenStore.Record(uid: original.uid, refreshToken: "fixture-rotated")
        try CloudTokenStore.save(rotated)
        let updated = try CloudTokenStore.load()
        precondition(updated?.refreshToken == rotated.refreshToken && updated?.displayName == nil)
        try checkPermissions()
        try Data("invalid".utf8).write(to: file)
        do {
            _ = try CloudTokenStore.load()
            preconditionFailure("Corrupt sessions must fail closed")
        } catch is DecodingError { }
        try CloudTokenStore.clear()
        let cleared = try CloudTokenStore.load()
        precondition(cleared == nil)
        try CloudTokenStore.clear()
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        do {
            try CloudTokenStore.save(original)
            preconditionFailure("Unwritable session storage must report failure")
        } catch { }
        print("Development Google session persistence, rotation, permissions, corruption, sign-out, and write-failure checks passed")
    default: preconditionFailure("Expected write or read")
    }
}

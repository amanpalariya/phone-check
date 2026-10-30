import OSLog

/// Diagnostic reasons only: never record notification content, app identity, or keys.
enum PreviewDiagnostics {
    private static let logger = Logger(subsystem: "dev.phonecheck.mac", category: "NotificationPreview")
    static func record(_ reason: String) { logger.notice("\(reason, privacy: .public)") }
}

import Foundation

/// Presentation only: suppressing an alert never removes its mirrored notification.
public enum AlertPolicy {
    public static func shouldAlert(phoneInUse: Bool?, sentAt: Int64?, now: Int64) -> Bool {
        // Old LAN peers have no attention metadata. Preserve their existing behavior.
        guard let phoneInUse else { return true }
        guard let sentAt, sentAt >= now - 30_000, sentAt <= now + 10_000 else { return false }
        return !phoneInUse
    }
}

/// Newer phone activity wins over an older notification still in transit.
public struct PhoneAttentionState {
    public private(set) var inUse: Bool?
    private var observedAt: Int64 = 0
    public init() {}
    public mutating func update(inUse: Bool?, sentAt: Int64?, now: Int64) {
        guard let inUse, let sentAt, sentAt >= observedAt,
              sentAt >= now - 30_000, sentAt <= now + 10_000 else { return }
        self.inUse = inUse; observedAt = sentAt
    }
}

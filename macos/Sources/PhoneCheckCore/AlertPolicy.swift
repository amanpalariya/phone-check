import Foundation

/// Presentation only: suppressing an alert never removes its mirrored notification.
public enum AlertPolicy {
    public static func focusAllowsPreview(authorized: Bool, isFocused: Bool?) -> Bool {
        authorized && isFocused == false
    }
    public static func shouldPreview(_ notice: Notice, previous: Notice?) -> Bool {
        !notice.isMedia && notice.groupSummary != true && notice.audible == true &&
            !(notice.onlyAlertOnce == true && previous != nil)
    }

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

/// Tracks unchecked live changes, never turning a reconnect snapshot into new alerts.
public struct UncheckedNotifications {
    private var keys = Set<String>()
    public init() {}
    public var hasNew: Bool { !keys.isEmpty }
    public mutating func check() { keys.removeAll() }
    public mutating func receive(_ notice: Notice, previous: Notice?, checking: Bool) {
        guard !checking, !notice.isMedia, notice.groupSummary != true,
              previous?.revision != notice.revision else { return }
        keys.insert(notice.key)
    }
    public mutating func reconcile(_ notices: [Notice]) {
        keys.formIntersection(notices.filter { !$0.isMedia && $0.groupSummary != true }.map(\.key))
    }
}

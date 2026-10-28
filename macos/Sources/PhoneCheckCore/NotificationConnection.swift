import Foundation

/// An authenticated, ordered, bounded session. A reconnect is a new session and snapshot.
/// Implementations and callbacks run on the main queue; close must be idempotent.
public protocol NotificationConnection: AnyObject {
    var onMessage: ((Message) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func start()
    func send(_ message: Message)
    func close()
}

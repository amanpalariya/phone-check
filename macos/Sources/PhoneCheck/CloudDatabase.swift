import Foundation
import PhoneCheckCore

struct CloudSnapshot {
    let value: Any?
    func childSnapshot(forPath path: String) -> CloudSnapshot {
        var result = value
        for component in path.split(separator: "/") { result = (result as? [String: Any])?[String(component)] }
        return CloudSnapshot(value: result)
    }
}

/// HTTPS control state only. Notification frames use FirebaseRESTMailbox separately.
final class CloudReference {
    enum Event { case value }
    private let databaseURL: URL
    private let path: String
    private let account: CloudAccount
    private let network = URLSession(configuration: .ephemeral, delegate: FirebaseRedirectPolicy(), delegateQueue: nil)
    private var observers: [UUID: Task<Void, Never>] = [:]
    init(databaseURL: URL, path: String, account: CloudAccount) {
        self.databaseURL = databaseURL; self.path = path; self.account = account
    }
    func child(_ suffix: String) -> CloudReference {
        CloudReference(databaseURL: databaseURL, path: path + "/" + suffix, account: account)
    }
    func setValue(_ value: Any, completion: ((Error?, CloudReference) -> Void)? = nil) {
        write(value, method: "PUT", completion: completion)
    }
    func removeValue(completion: ((Error?, CloudReference) -> Void)? = nil) {
        write(NSNull(), method: "PUT", completion: completion)
    }
    func updateChildValues(_ values: [String: Any], completion: ((Error?, CloudReference) -> Void)? = nil) {
        write(values, method: "PATCH", completion: completion)
    }
    private func write(_ value: Any, method: String, completion: ((Error?, CloudReference) -> Void)?) {
        Task { @MainActor in
            do {
                var request = try await request(method: method)
                request.httpBody = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
                let (_, response) = try await network.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FirebaseRESTError.response }
                completion?(nil, self)
            } catch { completion?(FirebaseRESTError.response, self) }
        }
    }
    func observe(_ event: Event, with changed: @escaping (CloudSnapshot) -> Void,
                 withCancel cancelled: @escaping (Error) -> Void) -> UUID {
        let id = UUID()
        observers[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            var delay: UInt64 = 1
            while !Task.isCancelled {
                do {
                    let request = try await request(method: "GET", stream: true)
                    let (bytes, response) = try await network.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200,
                          (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
                        throw FirebaseRESTError.response
                    }
                    var parser = FirebaseControlStream()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if try parser.append(byte) { delay = 1; changed(CloudSnapshot(value: parser.value)) }
                    }
                    throw FirebaseRESTError.stream
                } catch {
                    guard !Task.isCancelled else { break }
                    cancelled(FirebaseRESTError.stream)
                    do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { break }
                    delay = min(delay * 2, 15)
                }
            }
        }
        return id
    }
    func removeObserver(withHandle id: UUID) { observers.removeValue(forKey: id)?.cancel() }
    private func request(method: String, stream: Bool = false) async throws -> URLRequest {
        let token = try await account.idToken()
        var components = URLComponents(url: databaseURL.appendingPathComponent(path + ".json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "auth", value: token)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: stream ? 3600 : 15)
        request.httpMethod = method
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    deinit { observers.values.forEach { $0.cancel() }; network.invalidateAndCancel() }
}

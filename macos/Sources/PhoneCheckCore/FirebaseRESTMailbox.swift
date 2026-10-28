import Foundation

public enum FirebaseRESTError: Error { case configuration, response, stream }

/// Credentials are Firebase Auth ID tokens, refreshed by the caller. Never use an API key,
/// database secret, service-account credential or an Admin SDK in a device app.
public final class FirebaseRESTMailbox: FirebaseMailbox {
    private let network = URLSession(configuration: .ephemeral, delegate: FirebaseRedirectPolicy(), delegateQueue: nil)
    private let baseURL: URL
    private let idToken: () async throws -> String
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var closed = false

    public init(databaseURL: URL, pairID: String, sessionID: String,
                idToken: @escaping () async throws -> String) throws {
        guard databaseURL.scheme == "https", let host = databaseURL.host,
              host.hasSuffix(".firebaseio.com") || host.hasSuffix(".firebasedatabase.app"),
              databaseURL.port == nil, databaseURL.user == nil, databaseURL.password == nil,
              databaseURL.query == nil, databaseURL.fragment == nil,
              databaseURL.path.isEmpty || databaseURL.path == "/",
              !pairID.isEmpty, pairID.count <= 128,
              pairID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              UUID(uuidString: sessionID) != nil else { throw FirebaseRESTError.configuration }
        baseURL = databaseURL.appendingPathComponent("pairs").appendingPathComponent(pairID)
            .appendingPathComponent("sessions").appendingPathComponent(sessionID)
        self.idToken = idToken
    }
    public func observe(_ path: String, changed: @escaping (Result<String?, Error>) -> Void) -> () -> Void {
        let id = UUID()
        tasks[id] = Task { @MainActor [weak self] in
            guard let self, !self.closed else { return }
            defer { self.tasks.removeValue(forKey: id) }
            do {
                let request = try await self.request(path, method: "GET")
                let (bytes, response) = try await self.network.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
                    throw FirebaseRESTError.response
                }
                var parser = FirebaseEventStream()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    if case .value(let value) = try parser.append(byte) { changed(.success(value)) }
                }
                throw FirebaseRESTError.stream
            } catch {
                if !Task.isCancelled && !self.closed { changed(.failure(FirebaseRESTError.stream)) }
            }
        }
        return { [weak self] in self?.tasks.removeValue(forKey: id)?.cancel() }
    }
    public func write(_ path: String, value: String, completion: @escaping (Error?) -> Void) {
        let id = UUID()
        tasks[id] = Task { @MainActor [weak self] in
            guard let self, !self.closed else { return }
            defer { self.tasks.removeValue(forKey: id) }
            do {
                guard value.utf8.count <= Wire.maxFrame * 2 else { throw FirebaseRESTError.response }
                var request = try await self.request(path, method: "PUT")
                request.httpBody = try JSONEncoder().encode(value)
                // Avoid echoing notification ciphertext in the HTTP response.
                let (_, response) = try await self.network.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 204 else { throw FirebaseRESTError.response }
                if !Task.isCancelled && !self.closed { completion(nil) }
            } catch {
                if !Task.isCancelled && !self.closed { completion(FirebaseRESTError.response) }
            }
        }
    }
    private func request(_ path: String, method: String) async throws -> URLRequest {
        guard !closed, ["phoneToMac", "macToPhone", "phoneToMacAck", "macToPhoneAck"].contains(path) else {
            throw FirebaseRESTError.configuration
        }
        let token = try await idToken()
        guard !token.isEmpty else { throw FirebaseRESTError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent(path + ".json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "auth", value: token)]
        if method == "PUT" { components.queryItems?.append(URLQueryItem(name: "print", value: "silent")) }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: method == "GET" ? 3600 : 15)
        request.httpMethod = method
        request.setValue(method == "GET" ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    public func close() {
        closed = true; network.invalidateAndCancel()
        let running = Array(tasks.values); tasks.removeAll()
        running.forEach { $0.cancel() }
    }
    deinit { tasks.values.forEach { $0.cancel() } }
}

private final class FirebaseRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard response.statusCode == 307, let url = request.url, url.scheme == "https",
              url.port == nil, url.user == nil, url.password == nil, let host = url.host,
              host.hasSuffix(".firebaseio.com") || host.hasSuffix(".firebasedatabase.app") else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

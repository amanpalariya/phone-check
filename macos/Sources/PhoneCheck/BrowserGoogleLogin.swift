import AppKit
import CryptoKit
import Network
import PhoneCheckCore

/// OAuth authorization code + PKCE in the system browser. The callback binds only loopback.
/// The short-lived Google token is exchanged for Firebase credentials and is never persisted.
final class BrowserGoogleLogin {
    private let clientID: String
    private let clientSecret: String
    private let completion: (Result<String, Error>) -> Void
    private let verifier = BrowserGoogleLogin.urlSafe(Wire.random())
    private let state = BrowserGoogleLogin.urlSafe(Wire.random())
    private let nonce = BrowserGoogleLogin.urlSafe(Wire.random())
    private var listener: NWListener?
    private var timeout: DispatchWorkItem?
    private var connections: [UUID: NWConnection] = [:]
    private var redirect = ""
    private var finished = false
    init(clientID: String, clientSecret: String, completion: @escaping (Result<String, Error>) -> Void) {
        self.clientID = clientID; self.clientSecret = clientSecret; self.completion = completion
    }
    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, self.connections.count < 4, !self.finished else { connection.cancel(); return }
                let id = UUID(); self.connections[id] = connection
                connection.start(queue: .main); self.receive(connection, id: id, bytes: Data())
            }
            listener.stateUpdateHandler = { [weak self, weak listener] status in
                guard let self, !self.finished else { return }
                switch status {
                case .ready:
                    guard let port = listener?.port else { self.finish(.failure(FirebaseRESTError.configuration)); return }
                    self.redirect = "http://127.0.0.1:\(port.rawValue)/callback"
                    var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                    url.queryItems = ["client_id": self.clientID, "redirect_uri": self.redirect,
                        "response_type": "code", "scope": "openid email profile", "state": self.state,
                        "nonce": self.nonce, "code_challenge_method": "S256",
                        "code_challenge": Self.urlSafe(Data(SHA256.hash(data: Data(self.verifier.utf8))))]
                        .map { URLQueryItem(name: $0.key, value: $0.value) }
                    if !NSWorkspace.shared.open(url.url!) { self.finish(.failure(FirebaseRESTError.configuration)) }
                case .failed: self.finish(.failure(FirebaseRESTError.response))
                default: break
                }
            }
            listener.start(queue: .main)
            let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(FirebaseRESTError.response)) }
            self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timeout)
        } catch { finish(.failure(FirebaseRESTError.configuration)) }
    }
    private func receive(_ connection: NWConnection, id: UUID, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, failure in
            guard let self, !self.finished else { connection.cancel(); return }
            let bytes = bytes + (chunk ?? Data())
            guard failure == nil, bytes.count <= 8192 else { connection.cancel(); self.connections.removeValue(forKey: id); return }
            guard bytes.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete { connection.cancel(); self.connections.removeValue(forKey: id) }
                else { self.receive(connection, id: id, bytes: bytes) }
                return
            }
            guard let text = String(data: bytes, encoding: .utf8),
                  let first = text.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let parts = first.split(separator: " ")
            guard parts.count == 3, parts[0] == "GET",
                  let callback = URLComponents(string: self.redirect.components(separatedBy: "/callback")[0] + String(parts[1])),
                  callback.path == "/callback",
                  callback.queryItems?.filter({ $0.name == "state" }).count == 1,
                  callback.queryItems?.first(where: { $0.name == "state" })?.value == self.state else {
                self.respond(connection, text: "Invalid sign-in callback.", status: "400 Bad Request", id: id); return
            }
            let code = callback.queryItems?.first(where: { $0.name == "code" })?.value
            self.respond(connection, text: "Return to Phone Check. You can close this window.", id: id)
            self.listener?.cancel(); self.listener = nil
            guard let code, !code.isEmpty else { self.finish(.failure(FirebaseRESTError.response)); return }
            self.exchange(code)
        }
    }
    private func respond(_ connection: NWConnection, text: String, status: String = "200 OK", id: UUID) {
        let body = Data(text.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in
            connection.cancel(); self?.connections.removeValue(forKey: id)
        })
    }
    private func exchange(_ code: String) {
        Task { @MainActor in
            do {
                var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
                request.httpMethod = "POST"; request.timeoutInterval = 15
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(CloudAccount.form(["code": code, "client_id": clientID, "client_secret": clientSecret,
                    "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier]).utf8)
                let network = URLSession(configuration: .ephemeral)
                defer { network.finishTasksAndInvalidate() }
                let (data, response) = try await network.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = json["id_token"] as? String, token.utf8.count <= 16_384 else { throw FirebaseRESTError.response }
                let pieces = token.split(separator: ".")
                guard pieces.count == 3 else { throw FirebaseRESTError.response }
                var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
                guard let payload = Data(base64Encoded: encoded),
                      let claims = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                      claims["nonce"] as? String == nonce, claims["aud"] as? String == clientID else { throw FirebaseRESTError.response }
                // Firebase subsequently verifies the token signature, issuer, audience and expiry.
                finish(.success(token))
            } catch { finish(.failure(FirebaseRESTError.response)) }
        }
    }
    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true; timeout?.cancel(); listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        completion(result)
    }
    private static func urlSafe(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

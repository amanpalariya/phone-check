import AppKit
import Combine
import Foundation
import PhoneCheckCore

/// Google OAuth in the system browser. Only a Firebase refresh token is persisted locally.
final class CloudAccount: ObservableObject {
    static let shared = CloudAccount()
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private(set) var configured = false
    private(set) var projectID = ""
    private(set) var databaseURL: URL?
    private var apiKey = ""
    private var clientID = ""
    private var clientSecret = ""
    private var record: CloudTokenStore.Record?
    private var token: String?
    private var expiry = Date.distantPast
    private var refresh: Task<String, Error>?
    private var login: BrowserGoogleLogin?
    private let network = URLSession(configuration: .ephemeral)
    var onChange: (() -> Void)?
    var uid: String? { signedIn ? record?.uid : nil }
    var root: CloudReference? {
        guard let uid, let databaseURL else { return nil }
        return CloudReference(databaseURL: databaseURL, path: "accounts/\(uid)", account: self)
    }
    private init() {
        #if PHONECHECK_VISUAL_TEST
        signedIn = true
        return
        #else
        guard let path = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: path),
              let config = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let project = config["PROJECT_ID"] as? String, let key = config["API_KEY"] as? String,
              let endpoint = config["DATABASE_URL"] as? String, let url = URL(string: endpoint),
              url.scheme == "https", let host = url.host,
              host.hasSuffix(".firebaseio.com") || host.hasSuffix(".firebasedatabase.app"),
              url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let oauthURL = Bundle.main.url(forResource: "GoogleOAuthClient", withExtension: "json"),
              let oauthData = try? Data(contentsOf: oauthURL),
              let oauth = try? JSONSerialization.jsonObject(with: oauthData) as? [String: Any],
              let installed = oauth["installed"] as? [String: Any], installed["project_id"] as? String == project,
              let client = installed["client_id"] as? String, client.hasSuffix(".apps.googleusercontent.com"),
              let secret = installed["client_secret"] as? String else { error = "Google login configuration unavailable"; return }
        projectID = project; databaseURL = url; apiKey = key; clientID = client; clientSecret = secret
        configured = true
        do { record = try CloudTokenStore.load(); signedIn = record != nil }
        catch { self.error = "Login storage unavailable" }
        #endif
    }
    func signIn() {
        guard configured, !busy else { return }
        busy = true; error = nil
        login = BrowserGoogleLogin(clientID: clientID, clientSecret: clientSecret) { [weak self] result in
            guard let self else { return }
            self.login = nil
            Task { @MainActor in
                defer { self.busy = false }
                do {
                    let googleToken = try result.get()
                    let response = try await self.postJSON(
                        "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(self.apiKey)",
                        body: ["postBody": Self.form(["id_token": googleToken, "providerId": "google.com"]),
                               "requestUri": "http://localhost", "returnSecureToken": true])
                    guard let uid = response["localId"] as? String, let refresh = response["refreshToken"] as? String,
                          let token = response["idToken"] as? String else { throw FirebaseRESTError.response }
                    let record = CloudTokenStore.Record(uid: uid, refreshToken: refresh)
                    try CloudTokenStore.save(record)
                    self.record = record; self.token = token; self.expiry = Date().addingTimeInterval(3500)
                    self.signedIn = true; self.error = nil; self.onChange?()
                } catch { self.error = "Could not sign in. Try again." }
            }
        }
        login?.start()
    }
    func idToken() async throws -> String {
        guard let record, signedIn else { throw FirebaseRESTError.configuration }
        if let token, expiry > Date().addingTimeInterval(60) { return token }
        if let refresh { return try await refresh.value }
        let task = Task { @MainActor () throws -> String in
            var request = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!)
            request.httpMethod = "POST"; request.timeoutInterval = 15
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(Self.form(["grant_type": "refresh_token", "refresh_token": record.refreshToken]).utf8)
            let (data, response) = try await network.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, status == 400 || status == 401 {
                self.record = nil; self.token = nil; self.signedIn = false
                try? CloudTokenStore.clear(); self.onChange?()
                throw FirebaseRESTError.response
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["user_id"] as? String == record.uid,
                  let token = json["id_token"] as? String, let nextRefresh = json["refresh_token"] as? String,
                  self.record?.uid == record.uid, signedIn else { throw FirebaseRESTError.response }
            let next = CloudTokenStore.Record(uid: record.uid, refreshToken: nextRefresh)
            try CloudTokenStore.save(next); self.record = next
            self.token = token; self.expiry = Date().addingTimeInterval(3500)
            return token
        }
        refresh = task
        defer { refresh = nil }
        return try await task.value
    }
    func signOut() {
        do { try CloudTokenStore.clear() } catch { self.error = "Could not sign out"; return }
        refresh?.cancel(); refresh = nil; record = nil; token = nil; signedIn = false; onChange?()
    }
    private func postJSON(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: endpoint)!); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FirebaseRESTError.response }
        return json
    }
    static func form(_ values: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return values.sorted(by: { $0.key < $1.key }).map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
    }
}

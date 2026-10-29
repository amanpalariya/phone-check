import Foundation
import PhoneCheckCore

/// One account, one explicit pair, one live mailbox session. No trusted server is required.
/// Offers and requests are authenticated with the device-only QR secret in addition to Auth.
final class CloudSync {
    private let root: CloudReference
    private let control: CloudReference
    private var credentials: Credentials
    private var observer: UUID?
    private var mailboxID: String?
    private var offeredRequest: String?
    private var rotation: Timer?
    private var generation = 0
    private var stopped = true
    var onPair: (Credentials) -> Bool = { _ in false }
    var onConnect: (FirebaseConnection) -> Void = { _ in }
    var onRevoke: () -> Void = {}
    var onError: (String) -> Void = { _ in }
    init(root: CloudReference, credentials: Credentials) { self.root = root; self.control = root.child("control"); self.credentials = credentials }
    func start() {
        stop(); stopped = false
        observer = control.observe(.value, with: { [weak self] snapshot in
            self?.receive(snapshot)
        }, withCancel: { [weak self] _ in
            self?.offeredRequest = nil; self?.rotation?.invalidate()
            self?.onError("Cloud connection interrupted")
        })
    }
    private func receive(_ snapshot: CloudSnapshot) {
        guard !stopped else { return }
        let pair = snapshot.childSnapshot(forPath: "pair")
        guard let id = pair.childSnapshot(forPath: "id").value as? String,
              id == credentials.pairID else { stop(); onRevoke(); return }
        if let peer = pair.childSnapshot(forPath: "phone").value as? String {
            guard UUID(uuidString: peer) != nil,
                  let proofText = pair.childSnapshot(forPath: "proof").value as? String,
                  let proof = Data(base64Encoded: proofText),
                  Wire.verify(proof, secret: credentials.secret, label: "cloud-pair", material: Data(peer.utf8)),
                  credentials.peer == nil || credentials.peer == peer else { onError("Pairing could not be verified"); return }
            if credentials.peer == nil {
                var next = credentials; next.peer = peer
                guard onPair(next) else { return }
                credentials = next
            }
        }
        guard let request = snapshot.childSnapshot(forPath: "request").value as? [String: Any],
              let requestID = request["id"] as? String, UUID(uuidString: requestID) != nil,
              let peer = request["peer"] as? String, peer == credentials.peer,
              let proofText = request["proof"] as? String, let proof = Data(base64Encoded: proofText),
              Wire.verify(proof, secret: credentials.secret, label: "cloud-request", material: Data("\(requestID)|\(peer)".utf8)) else { return }
        if requestID != offeredRequest { offer(requestID: requestID, peer: peer) }
    }
    private func offer(requestID: String, peer: String) {
        guard !stopped else { return }
        offeredRequest = requestID; generation += 1
        let epoch = generation
        let id = UUID().uuidString.lowercased()
        let now = Int64(Date().timeIntervalSince1970 * 1000), expiry = now + 840_000
        let proof = Wire.derive(credentials.secret, label: "cloud-offer", material: Data("\(id)|\(requestID)|\(peer)|\(expiry)".utf8)).base64EncodedString()
        // Replace every previous mailbox atomically. No growing notification/session history.
        root.updateChildValues(["mailboxes": NSNull(), "control/offer": [
            "id": id, "request": requestID, "expiresAt": expiry, "proof": proof
        ]]) { [weak self] failure, _ in
            guard let self, !self.stopped, epoch == self.generation else { return }
            guard failure == nil else {
                self.offeredRequest = nil; self.onError("Could not connect to Firebase"); return
            }
            do {
                guard let databaseURL = CloudAccount.shared.databaseURL, let uid = self.credentials.ownerUID,
                      let pairID = self.credentials.pairID else { throw FirebaseRESTError.configuration }
                self.mailboxID = id
                let mailbox = try FirebaseRESTMailbox(databaseURL: databaseURL, pairID: pairID, sessionID: id, ownerUID: uid) {
                    try await CloudAccount.shared.idToken()
                }
                let session = try FirebaseSession(id: id, secret: self.credentials.secret, expiresAt: expiry,
                                                  now: Int64(Date().timeIntervalSince1970 * 1000))
                self.onConnect(FirebaseConnection(mailbox: mailbox, session: session))
                self.rotation?.invalidate()
                self.rotation = Timer.scheduledTimer(withTimeInterval: 720, repeats: false) { [weak self] _ in
                    self?.offer(requestID: requestID, peer: peer)
                }
            } catch { self.offeredRequest = nil; self.onError("Could not start encrypted session") }
        }
    }
    func stop() {
        stopped = true; generation += 1
        if let observer { control.removeObserver(withHandle: observer) }
        observer = nil; offeredRequest = nil
        if let mailboxID { root.child("mailboxes/\(mailboxID)").removeValue() }
        mailboxID = nil
        rotation?.invalidate(); rotation = nil
    }
    deinit { rotation?.invalidate() }
}

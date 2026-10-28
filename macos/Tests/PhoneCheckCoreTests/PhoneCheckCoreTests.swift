import Foundation
import PhoneCheckCore

@main
struct PhoneCheckCoreTests {
    static func main() throws {
        let tests = Self()
        try tests.testSnapshotDoesNotReplayAndUpdatesDeduplicate()
        try tests.testStaleDismissalCannotRemoveUpdatedNotice()
        try tests.testDisconnectClearsStateAndRequiresSnapshot()
        try tests.testDirectionKeyGoldenVectorAndProofBinding()
        try tests.testCipherRejectsReplayReorderTamperingAndWrongDirection()
        try tests.testFrameLimitsAndJSONRoundTrip()
        try tests.testRichAndLegacyNoticeDecoding()
        print("7 core checks passed")
        try FirebaseChecks.run()
    }
    private func notice(_ revision: String = "one", key: String = "k") -> Notice {
        Notice(key: key, app: "Mail", title: "Subject", body: "Text", revision: revision, dismissible: true, postedAt: 1)
    }
    func testSnapshotDoesNotReplayAndUpdatesDeduplicate() throws {
        var state = ActiveState()
        try check({ !state.upsert(notice()) }())
        state.snapshot([notice()])
        try check({ !state.upsert(notice()) }())
        try check({ state.upsert(notice("two")) }())
        state.snapshot([notice("three", key: "other")])
        try check(state.items["k"] == nil)
        try check(state.items.count == 1)
    }
    func testStaleDismissalCannotRemoveUpdatedNotice() throws {
        var state = ActiveState()
        state.snapshot([notice("new")])
        try check({ !(state.remove("k", revision: "old")) }())
        try check(state.items.count == 1)
        try check({ state.remove("k", revision: "new") }())
    }
    func testDisconnectClearsStateAndRequiresSnapshot() throws {
        var state = ActiveState(); state.snapshot([notice()]); state.reset()
        try check(state.items.isEmpty); try check(!(state.synchronized))
        try check({ !state.upsert(notice()) }())
    }
    func testDirectionKeyGoldenVectorAndProofBinding() throws {
        let key = Data(0..<32)
        let material = Wire.material(Data(0..<32), Data(32..<64), "00000000-0000-0000-0000-000000000001")
        let derived = Wire.derive(key, label: "c2s", material: material)
        try check(derived.map { String(format: "%02x", $0) }.joined() == "39afc19d399f1c164d12f101a63f3dbe9a6f0c8706bf9fb6e82e492fc8bfcb58")
        let proof = Wire.derive(key, label: "client-proof", material: material)
        try check(Wire.verify(proof, secret: key, label: "client-proof", material: material))
        try check(!(Wire.verify(proof, secret: key, label: "server-proof", material: material)))
        try check(!(Wire.verify(proof, secret: key, label: "client-proof", material: material + Data([0]))))
    }
    func testCipherRejectsReplayReorderTamperingAndWrongDirection() throws {
        let key = Data(0..<32), plain = Data("Phone Check".utf8)
        let sender = Cipher(key: key), receiver = Cipher(key: key)
        let first = try sender.seal(plain), second = try sender.seal(plain)
        try check(try receiver.open(first) == plain)
        try checkThrows { try receiver.open(first) }
        try check(try receiver.open(second) == plain)
        try checkThrows { try Cipher(key: key).open(second) }
        var corrupt = first; corrupt[corrupt.startIndex] ^= 1
        try checkThrows { try Cipher(key: key).open(corrupt) }
        try checkThrows { try Cipher(key: Data(repeating: 1, count: 32)).open(first) }
        // Same vector is checked on the JVM to cover Swift/JCA interoperability.
        try check(first.map { String(format: "%02x", $0) }.joined() == "5ed4dab0d00cc0d56dcbc22465663226decf0eeb3dc7c106df0005")
    }
    func testRichAndLegacyNoticeDecoding() throws {
        let legacy = notice()
        let decoded = try JSONDecoder().decode(Notice.self, from: JSONEncoder().encode(legacy))
        try check(decoded.actions == nil && decoded.image == nil && decoded.alertText == "Text")
        let json = #"{"key":"chat","app":"Chat","title":"Team","body":"Fallback","revision":"r","dismissible":true,"postedAt":1,"kind":"messaging","messages":[{"sender":"Alex","text":"Hello","time":1,"attachment":false},{"sender":"Jo","text":"","time":2,"attachment":true}],"actions":[{"id":"reply","title":"Reply","input":true,"freeform":true,"choices":["Yes"],"enabled":true,"requiresUnlock":false,"destructive":false}],"openable":true}"#
        let rich = try JSONDecoder().decode(Notice.self, from: Data(json.utf8))
        try check(rich.alertText == "Alex: Hello\nJo: Attachment")
        try check(rich.actions?.first?.choices == ["Yes"])
        var frame = Message("upsert"); frame.item = rich
        try check(try Wire.decode(Wire.json(frame)).item == rich)
        var progress = legacy
        progress.progress = try JSONDecoder().decode(NoticeProgress.self, from: Data(#"{"value":25,"max":100,"indeterminate":false}"#.utf8))
        try check(progress.alertText == "Text\n25 / 100")
    }
    func testFrameLimitsAndJSONRoundTrip() throws {
        try checkThrows { try Wire.frame(Data()) }
        try checkThrows { try Wire.frame(Data(repeating: 0, count: Wire.maxFrame + 1)) }
        var message = Message("snapshot"); message.items = [notice()]
        let data = try Wire.json(message)
        try check(try Wire.decode(data).items == message.items)
        let framed = try Wire.frame(data)
        try check(framed.prefix(4).reduce(0) { $0 << 8 | Int($1) } == data.count)
    }
}

private struct CheckFailure: Error { let line: UInt }
private func check(_ condition: @autoclosure () throws -> Bool, line: UInt = #line) throws {
    guard try condition() else { throw CheckFailure(line: line) }
}
private func checkThrows(_ action: () throws -> Any, line: UInt = #line) throws {
    var threw = false
    do { _ = try action() } catch { threw = true }
    guard threw else { throw CheckFailure(line: line) }
}

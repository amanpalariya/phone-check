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
        try tests.testNotificationGroupsPreserveMembersAndAppBoundaries()
        try tests.testRepeatedKeysAndGroupSummariesDoNotInflateCounts()
        try tests.testSummaryFirstMessageUpdatesAcrossApps()
        try tests.testBatteryMessage()
        try tests.testMediaTimelineAndNotificationSeparation()
        try tests.testUncheckedNotificationsAndPreviewPolicy()
        print("13 core checks passed")
        try FirebaseChecks.run()
    }
    func testUncheckedNotificationsAndPreviewPolicy() throws {
        var unread = UncheckedNotifications()
        var first = notice(key: "first")
        unread.reconcile([first])
        try check(!unread.hasNew) // Initial/reconnect snapshots never create unread alerts.
        unread.receive(first, previous: nil, checking: false)
        try check(unread.hasNew)
        unread.check()
        unread.receive(first, previous: first, checking: false)
        try check(!unread.hasNew)
        var update = first; update.revision = String(repeating: "b", count: 64)
        unread.receive(update, previous: first, checking: true)
        try check(!unread.hasNew)
        unread.receive(update, previous: first, checking: false)
        unread.reconcile([update])
        try check(unread.hasNew)
        unread.reconcile([])
        try check(!unread.hasNew)
        var summary = first; summary.groupSummary = true
        var media = first; media.kind = "media"
        unread.receive(summary, previous: nil, checking: false)
        unread.receive(media, previous: nil, checking: false)
        try check(!unread.hasNew)
        try check(!AlertPolicy.shouldPreview(first, previous: nil)) // Older peers lack sound metadata.
        first.audible = true
        try check(AlertPolicy.shouldPreview(first, previous: nil))
        first.onlyAlertOnce = true
        try check(AlertPolicy.shouldPreview(first, previous: nil))
        try check(!AlertPolicy.shouldPreview(first, previous: first))
        first.audible = false
        try check(!AlertPolicy.shouldPreview(first, previous: nil))
        try check(!AlertPolicy.shouldPreview(summary, previous: nil))
        try check(!AlertPolicy.shouldPreview(media, previous: nil))
        try check(AlertPolicy.focusAllowsPreview(authorized: true, isFocused: false))
        try check(!AlertPolicy.focusAllowsPreview(authorized: true, isFocused: true))
        try check(!AlertPolicy.focusAllowsPreview(authorized: true, isFocused: nil))
        try check(!AlertPolicy.focusAllowsPreview(authorized: false, isFocused: false))
        let decoded = try JSONDecoder().decode(Notice.self, from: JSONEncoder().encode(first))
        try check(decoded.audible == false && decoded.onlyAlertOnce == true)
    }
    func testMediaTimelineAndNotificationSeparation() throws {
        var media = notice(key: "player")
        media.kind = "media"
        media.media = try JSONDecoder().decode(NoticeMedia.self, from: Data(#"{"playing":true,"buffering":false,"position":10000,"duration":20000,"speed":1,"updatedAt":100000}"#.utf8))
        try check(media.media!.position(at: Date(timeIntervalSince1970: 105)) == 15000)
        try check(media.media!.position(at: Date(timeIntervalSince1970: 200)) == 20000)
        media.media?.playing = false
        try check(media.media!.position(at: Date(timeIntervalSince1970: 200)) == 10000)
        let actionJSON = #"{"id":"opaque","title":"Siguiente","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false,"mediaControl":"next","icon":"abc"}"#
        media.actions = [try JSONDecoder().decode(NoticeAction.self, from: Data(actionJSON.utf8))]
        let roundTrip = try JSONDecoder().decode(Notice.self, from: JSONEncoder().encode(media))
        try check(roundTrip == media && roundTrip.actions?.first?.mediaControl == "next")
        try check(NotificationSection.count([media, notice()]) == 1)
        try check(NotificationSection.sections([media]).isEmpty)
    }
    func testBatteryMessage() throws {
        // The Android JSON shape, including a missing/unknown battery percentage.
        for json in [#"{"type":"device_status","battery":{"percentage":42,"charging":true,"powerSaving":true}}"#,
                     #"{"type":"device_status","battery":{"percentage":42,"charging":true}}"#,
                     #"{"type":"device_status","battery":{"percentage":null,"charging":false}}"#] {
            let message = try Wire.decode(Data(json.utf8))
            try check(message.battery?.isValid == true)
            let decoded = try Wire.decode(Wire.json(message))
            try check(decoded.battery == message.battery)
        }
        for percentage in [-1, 101] {
            try check(!BatteryStatus(percentage: percentage, charging: false).isValid)
        }
        try check(BatteryStatus(percentage: 0, charging: false).isValid)
        try check(BatteryStatus(percentage: 100, charging: true).isValid)
    }
    private func notice(_ revision: String = "one", key: String = "k") -> Notice {
        Notice(key: key, app: "Mail", title: "Subject", body: "Text", revision: revision, dismissible: true, postedAt: 1)
    }
    func testSummaryFirstMessageUpdatesAcrossApps() throws {
        var state = ActiveState(); state.snapshot([])
        for (app, package) in [("Gmail", "com.google.android.gm"), ("Slack", "com.Slack")] {
            var summary = notice(key: "\(app)-summary")
            summary.app = app; summary.packageName = package
            summary.groupKey = "messages"; summary.groupSummary = true; summary.openable = true
            _ = state.upsert(summary)
            var message = summary
            message.key = "\(app)-message"; message.groupSummary = false
            for revision in ["first", "second", "second"] {
                message.revision = revision
                _ = state.upsert(message)
            }
        }
        let sections = NotificationSection.sections(Array(state.items.values))
        try check(sections.count == 2)
        try check(sections.allSatisfy { $0.children.isEmpty && $0.notice.groupSummary == false && $0.summary != nil })
        try check(NotificationSection.count(Array(state.items.values)) == 2)
        _ = state.remove("Gmail-summary")
        try check(NotificationSection.count(Array(state.items.values)) == 2)
    }
    func testRepeatedKeysAndGroupSummariesDoNotInflateCounts() throws {
        var first = notice(key: "first"); first.groupKey = "chat"
        var second = first; second.key = "second"
        var summary = first; summary.key = "summary"; summary.groupSummary = true; summary.openable = true
        let notices = [first, summary, second, first]
        let sections = NotificationSection.sections(notices)
        try check(sections.count == 1 && sections[0].children.map(\.key) == ["first", "second"])
        try check(NotificationSection.count(notices) == 2)
        try check(NotificationSection.count([summary, first]) == 1)
        try check(NotificationSection.count([summary]) == 1)
        // Same text from two independent Android keys must remain two notices.
        try check(NotificationSection.count([notice(key: "a"), notice(key: "b")]) == 2)
        var state = ActiveState()
        state.snapshot(notices)
        try check(state.items.count == 3)
        for index in 0..<5 {
            first.revision = "update-\(index)"
            try check({ state.upsert(first) }())
            try check(NotificationSection.count(Array(state.items.values)) == 2)
        }
        try check(state.items["first"]?.revision == "update-4")
        _ = state.remove("second")
        try check(NotificationSection.count(Array(state.items.values)) == 1)
    }
    func testNotificationGroupsPreserveMembersAndAppBoundaries() throws {
        var first = notice(key: "first"); first.groupKey = "inbox"
        var second = first; second.key = "second"
        var summary = first; summary.key = "summary"; summary.groupSummary = true
        var otherApp = first; otherApp.key = "other"; otherApp.app = "Chat"
        let ungrouped = notice(key: "ungrouped")
        let sections = NotificationSection.sections([first, ungrouped, summary, second, otherApp])
        try check(sections.count == 3)
        try check(sections[0].notice.key == first.key)
        try check(sections[0].summary?.key == summary.key)
        try check(sections[0].children.map(\.key) == ["first", "second"])
        try check(sections[1].notice.key == "ungrouped" && sections[1].children.isEmpty)
        try check(sections[2].notice.key == "other" && sections[2].children.isEmpty)
        let orphan = NotificationSection.sections([first, second])
        try check(orphan.count == 1 && orphan[0].children.count == 2)
        try check(orphan[0].id == sections[0].id)
        let single = NotificationSection.sections([second])
        try check(single.count == 1 && single[0].notice.key == "second" && single[0].children.isEmpty)
        for members in [[summary, second], [second, summary], [summary, second, second]] {
            let singleChild = NotificationSection.sections(members)
            try check(singleChild.count == 1)
            try check(singleChild[0].notice.key == "second" && singleChild[0].children.isEmpty)
            try check(singleChild[0].summary?.key == "summary")
            try check(singleChild[0].id == single[0].id)
        }
        let afterRemoval = NotificationSection.sections([summary, first])
        try check(afterRemoval.count == 1 && afterRemoval[0].children.isEmpty)
        try check(afterRemoval[0].notice.key == "first")
        let loneSummary = NotificationSection.sections([summary])
        try check(loneSummary.count == 1 && loneSummary[0].notice.key == "summary")
        let empty = NotificationSection.sections([])
        try check(empty.isEmpty)
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

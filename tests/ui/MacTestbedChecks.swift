import Foundation
import PhoneCheckCore

func runTestbedChecks() {
    let model = NotificationTestbed()
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
    for kind in NotificationFixtures.Kind.allCases {
        let samples = NotificationFixtures.make(kind)
        precondition(!samples.isEmpty && Set(samples.map(\.key)).count == samples.count)
        for sample in samples {
            precondition(NoticeImage.icon(sample) != nil, "Fixture icon must decode")
            if sample.image != nil { precondition(NoticeImage.image(sample) != nil, "Picture must decode") }
        }
        model.show(kind)
        let count = model.notices.count
        model.show(kind)
        precondition(model.notices.count == count, "Repeated samples must update in place")
    }
    model.showAll()
    precondition(NotificationSection.count(model.notices) == NotificationFixtures.Kind.allCases.count + 2)
    model.clear()
    model.show(.text)
    let original = model.notices[0]
    model.updateLatest()
    precondition(model.notices[0].revision != original.revision)
    model.commands.dismiss(original)
    precondition(model.commands.pendingKeys.isEmpty, "Stale commands must not execute")
    model.commands.dismiss(model.notices[0])
    precondition(!model.notices.isEmpty, "Dismissal must wait for its simulated confirmation")
    settle()
    precondition(model.notices.isEmpty)
    model.show(.group)
    model.commands.dismiss(model.notices.first { $0.groupSummary == true }!)
    settle()
    precondition(model.notices.isEmpty, "Group dismissal must remove its children")
    model.show(.messaging)
    let chat = model.notices[0]
    let action = chat.actions![0]
    model.commands.beginReply(chat, action: action)
    model.commands.perform(chat, action: action, text: "Yes")
    settle()
    precondition(model.commands.replyTarget == nil && model.receipt.contains("Yes"))
    model.result = "failed"
    model.commands.dismiss(chat)
    settle()
    precondition(model.notices.count == 1 && model.commands.feedback[chat.key] == "Phone action failed")
    model.clear()
    model.show(.ongoing)
    model.commands.dismiss(model.notices[0])
    precondition(model.commands.pendingKeys.isEmpty)
    model.show(.text)
    model.result = "sent"
    model.commands.dismiss(model.notices.last!)
    model.clear()
    model.show(.text)
    settle()
    precondition(model.notices.count == 1 && model.receipt.isEmpty, "Cleared commands must not affect new samples")
    model.clear()
    print("Mac testbed fixture, update, reply, dismissal, failure, and reset checks passed")
}

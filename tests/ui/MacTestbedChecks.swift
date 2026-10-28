import AppKit
import SwiftUI
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


func runPaneChecks() {
    let screen = NSRect(x: -1440, y: 180, width: 1440, height: 850)
    let anchor = NSRect(x: -800, y: screen.maxY, width: 30, height: 24)
    let frame = NotificationPaneLayout.frame(in: screen, anchor: anchor)
    precondition(frame.midX == anchor.midX && frame.maxY == anchor.minY - 6)
    precondition(frame.height == 680 && screen.contains(frame), "Pane must fit secondary screens with negative origins")
    for x in [screen.minX, screen.maxX - 20] {
        let edge = NotificationPaneLayout.frame(in: screen, anchor: NSRect(x: x, y: screen.maxY, width: 20, height: 24))
        precondition(screen.contains(edge), "Menu-bar anchors near either edge must stay onscreen")
    }
    let small = NSRect(x: 150, y: -400, width: 360, height: 400)
    precondition(small.contains(NotificationPaneLayout.frame(in: small, anchor: nil)), "Small screens must constrain the pane")
    precondition(NotificationPaneLayout.frame(in: screen, anchor: .zero).height == 680,
                 "An unpositioned status item must not collapse the pane")
    let model = Companion(startServices: false)
    let testbed = NotificationTestbed()
    testbed.showAll()
    testbed.showsInPane = true
    let controller = NotificationPaneController(model: model, testbed: testbed)
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
    controller.show()
    settle()
    let panel = NSApp.windows.compactMap { $0 as? NotificationPanel }.first!
    precondition(panel.isVisible && !panel.isOpaque && !panel.hasShadow)
    precondition(panel.styleMask.contains(.nonactivatingPanel) && !panel.styleMask.contains(.titled))
    let surface = panel.contentView as! NotificationPaneSurface
    if #available(macOS 26.0, *) {
        let glass = surface.backdrop as! NSGlassEffectView
        precondition(glass.style == .clear && glass.cornerRadius == 0 && glass.layer?.mask != nil)
    } else {
        let blur = surface.backdrop as! NSVisualEffectView
        precondition(blur.blendingMode == .behindWindow && blur.maskImage != nil)
    }
    precondition(surface.host.frame == surface.bounds, "Content must follow the anchored surface")
    func checkScroll(_ view: NSView) {
        if let scroll = view as? NotificationOverlayScrollView {
            precondition(scroll.scrollerStyle == .overlay)
            precondition(scroll.frame.height < panel.frame.height, "Feed must leave room for pane controls")
            precondition((scroll.documentView?.frame.width ?? 0) <= scroll.contentView.bounds.width + 1)
        }
        view.subviews.forEach(checkScroll)
    }
    checkScroll(surface)
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                                  charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    panel.sendEvent(escape)
    precondition(!panel.isVisible, "Escape must close the pane")
    controller.show()
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
    controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
    precondition(panel.isVisible, "Native menu tracking must not dismiss the pane")
    NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
    precondition(panel.contentView === surface, "Reopening must preserve presentation state")
    controller.perform(NSSelectorFromString("toggle"))
    precondition(!panel.isVisible, "Menu-bar toggle must close the pane")
    controller.perform(NSSelectorFromString("toggle"))
    precondition(panel.isVisible, "Menu-bar toggle must reopen the pane")
    let other = NSWindow(contentRect: NSRect(x: 10, y: 10, width: 100, height: 100),
                         styleMask: [.titled], backing: .buffered, defer: false)
    other.makeKeyAndOrderFront(nil)
    settle()
    precondition(!panel.isVisible, "Moving focus to another window must close the pane")
    other.orderOut(nil)
    controller.show()
    NotificationCenter.default.post(name: .init("PhoneCheckShow"), object: nil)
    settle()
    precondition(panel.isVisible, "Banner actions must reveal the same pane")
    controller.hide()
    print("Floating pane geometry, native blur, scrolling, Escape, menu toggle, focus dismissal and reopening checks passed")
}

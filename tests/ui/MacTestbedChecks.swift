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
    precondition(frame.midX == anchor.midX && frame.maxY == anchor.minY - 2)
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
    let originalSystem = NotificationAppearance.shared.usesSystemBackdrop
    NotificationAppearance.shared.usesSystemBackdrop = true
    controller.show()
    settle()
    let panel = NSApp.windows.compactMap { $0 as? NotificationPanel }.first!
    precondition(panel.isVisible && !panel.isOpaque && !panel.hasShadow)
    precondition(panel.styleMask.contains(.nonactivatingPanel) && !panel.styleMask.contains(.titled))
    let surface = panel.contentView as! NotificationPaneSurface
    precondition(surface.backdrop.material == .underWindowBackground)
    precondition(surface.backdrop.blendingMode == .behindWindow && surface.backdrop.maskImage != nil)
    if surface.compositor.isAvailable && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
        precondition(!surface.compositor.isHidden && surface.backdrop.isHidden,
                     "Use the blur-only renderer when available")
        precondition(surface.compositor.maskImage != nil && surface.compositor.frame == surface.backdrop.frame,
                     "Real blur must share the localized, feathered bounds")
    }
    let originalAppearance = surface.appearance
    for system in [NSAppearance.Name.aqua, .darkAqua] {
        surface.appearance = NSAppearance(named: system)
        settle()
        precondition(surface.backdrop.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                     "Backdrop must remain dark in both system appearances")
        let expected: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.32
        precondition(abs(surface.backdrop.alphaValue - expected) < 0.001)
        precondition(surface.host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == system)
    }
    surface.setContentHeight(120)
    surface.layoutSubtreeIfNeeded()
    precondition(surface.backdrop.frame.height == 186, "A short list must not leave a panel-sized backdrop")
    let maskTemplate = surface.backdrop.maskImage
    surface.setContentHeight(300)
    surface.layoutSubtreeIfNeeded()
    precondition(surface.backdrop.frame.height == 366, "Backdrop must follow visible content height")
    precondition(surface.backdrop.maskImage === maskTemplate,
                 "Animated backdrop resizing must reuse its feathered image template")
    NotificationAppearance.shared.usesSystemBackdrop = false
    settle()
    precondition(surface.backdrop.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                 "Custom strength must keep the backdrop dark")
    surface.appearance = originalAppearance
    NotificationAppearance.shared.usesSystemBackdrop = originalSystem
    settle()
    precondition(surface.host.frame == surface.bounds, "Content must follow the anchored surface")
    func checkScroll(_ view: NSView) {
        if let scroll = view as? NotificationOverlayScrollView {
            precondition(scroll.scrollerStyle == .overlay)
            precondition(scroll.frame.height < panel.frame.height, "Feed must leave room for pane controls")
            precondition((scroll.documentView?.frame.width ?? 0) <= scroll.contentView.bounds.width + 1)
            if let document = scroll.documentView {
                let origin = scroll.contentView.bounds.origin
                let bottom = document.isFlipped ? max(document.bounds.minY, document.bounds.maxY - scroll.contentView.bounds.height) : document.bounds.minY
                scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                precondition(!scroll.hasMoreBelow,
                             "The final notification must not remain faded at the end")
                if document.frame.height > scroll.contentView.bounds.height + 1 {
                    precondition(scroll.hasMoreAbove && scroll.contentView.layer?.mask != nil,
                                 "Notifications above the viewport need a top fade cue")
                    let top = document.isFlipped ? document.bounds.minY : document.bounds.maxY - scroll.contentView.bounds.height
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    precondition(!scroll.hasMoreAbove && scroll.hasMoreBelow && scroll.contentView.layer?.mask != nil,
                                 "Overflowing notifications need a bottom fade cue")
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: (top + bottom) / 2))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    precondition(scroll.hasMoreAbove && scroll.hasMoreBelow,
                                 "Both edges need fade cues in the middle of the list")
                } else {
                    precondition(!scroll.hasMoreAbove && scroll.contentView.layer?.mask == nil,
                                 "A list that fits must have no edge fades")
                }
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
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

private final class MotionProbeState: ObservableObject {
    var contentEvaluations = 0
    @Published var height: CGFloat = 120
    @Published var notices = NotificationFixtures.make(.group)
    @Published var query = ""
}

private struct MotionProbe: View {
    @ObservedObject var state: MotionProbeState
    var body: some View {
        NotificationScroll(contentHeight: state.height) {
            let _ = state.contentEvaluations += 1
            Color.clear.frame(height: state.height)
        }
        .frame(width: 320, height: min(300, state.height))
        .notificationMotion(value: state.height)
    }
}

func runMotionChecks() {
    let expansion = NotificationExpansionState()
    let group = NotificationFixtures.make(.group)
    let children = group.filter { $0.groupSummary != true }
    let section = NotificationSection.sections(group)[0]
    let key = children[0].key
    expansion.row(key).wrappedValue = true
    expansion.group(section.id).wrappedValue = true
    expansion.group(section.id).wrappedValue = false
    precondition(expansion.row(key).wrappedValue, "Collapsing a group must preserve child expansion")
    expansion.group(section.id).wrappedValue = true
    expansion.retain(notices: Array(group.reversed()))
    precondition(expansion.row(key).wrappedValue && expansion.group(section.id).wrappedValue,
                 "Reordering active notifications must preserve expansion")
    expansion.retain(notices: [children[0]])
    precondition(expansion.row(key).wrappedValue, "A group becoming a singleton must preserve its child expansion")
    expansion.retain(notices: [])
    precondition(expansion.rows.isEmpty && expansion.groups.isEmpty, "Removed notifications must release presentation state")
    precondition(NotificationMotion.animation(reduceMotion: true) == nil)

    // Exercise the actual representable, sampling document size while SwiftUI
    // interpolates it. A final-height snap cannot pass this test.
    let state = MotionProbeState()
    let host = NSHostingView(rootView: MotionProbe(state: state))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    func settle(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
    func findScroll(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NotificationOverlayScrollView { return scroll }
        return view.subviews.compactMap(findScroll).first
    }
    settle(0.1)
    let scroll = findScroll(host)!
    let evaluationsBeforeAnimation = state.contentEvaluations
    state.height = 480
    var samples: [CGFloat] = []
    for _ in 0..<10 {
        settle(0.02)
        samples.append(scroll.documentView!.frame.height)
    }
    precondition(samples.contains { $0 > 121 && $0 < 479 }, "Document height must interpolate, not snap")
    let contentUpdates = state.contentEvaluations - evaluationsBeforeAnimation
    precondition(contentUpdates < 8, "Geometry frames must not rebuild hosted content (\(contentUpdates) updates)")
    let hosted = scroll.documentView!.subviews.compactMap { $0 as? NSHostingView<AnyView> }.first!
    precondition(hosted.frame.minY == 0 && abs(hosted.frame.height - 480) < 1,
                 "Hosting layout must stay top-pinned at the destination size")
    print("Scroll resize content evaluations: \(contentUpdates) across 10 frame samples")
    // Retarget before completion, then shrink below the viewport and grow again.
    state.height = 60
    settle(0.04)
    state.height = 240
    settle(0.5)
    precondition(abs(scroll.documentView!.frame.height - 240) < 1, "Interrupted resizing must settle at the newest height")
    state.height = 60
    settle(0.5)
    precondition(abs(scroll.documentView!.frame.height - 60) < 1)
    precondition(scroll.contentView.bounds.origin.y == 0, "Shrinking must clamp the viewport")
    window.orderOut(nil)

    let model = NotificationTestbed()
    let feedExpansion = NotificationExpansionState()
    let feed = NSHostingView(rootView: MotionFeedProbe(state: state, commands: model.commands, expansion: feedExpansion))
    let feedWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
    feedWindow.contentView = feed
    feedWindow.orderFront(nil)
    settle(0.4)
    let feedScroll = findScroll(feed)!
    func documentHeight() -> CGFloat { feedScroll.documentView!.frame.height }
    let collapsedHeight = documentHeight()
    feedExpansion.group(section.id).wrappedValue = true
    settle(0.5)
    precondition(documentHeight() > collapsedHeight + 20, "Opening a group must lay out all children")
    let openHeight = documentHeight()
    feedExpansion.row(key).wrappedValue = true
    settle(0.5)
    precondition(documentHeight() > openHeight, "Expanding a child must resize the scroll document")
    // Repeated expansion used to expose occasional scroll/reappear shifts.
    // Sample the whole transition, not just the settled final frame.
    func samplePinnedTransition(_ change: () -> Void, growing: Bool, anchorY: CGFloat = 0) {
        var previous = documentHeight()
        change()
        for _ in 0..<32 {
            settle(0.012)
            let current = documentHeight()
            precondition(abs(feedScroll.contentView.bounds.origin.y - anchorY) < 1,
                         "Top-anchored content must not scroll during expansion or collapse")
            precondition(growing ? current >= previous - 1 : current <= previous + 1,
                         "Repeated toggles must resize monotonically without reappearing jumps")
            previous = current
        }
    }
    for _ in 0..<4 {
        samplePinnedTransition({ feedExpansion.row(key).wrappedValue = false }, growing: false)
        samplePinnedTransition({ feedExpansion.row(key).wrappedValue = true }, growing: true)
        samplePinnedTransition({ feedExpansion.group(section.id).wrappedValue = false }, growing: false)
        samplePinnedTransition({ feedExpansion.group(section.id).wrappedValue = true }, growing: true)
    }
    feedExpansion.group(section.id).wrappedValue = false
    settle(0.04)
    feedExpansion.group(section.id).wrappedValue = true
    state.notices = Array(state.notices.reversed())
    settle(0.5)
    precondition(feedExpansion.rows.contains(key), "Interrupted group changes must preserve expanded children")
    state.query = "no fixture can match this query"
    settle(0.5)
    precondition(documentHeight() < collapsedHeight + 40, "Empty search must shrink the document")
    state.query = ""
    settle(0.5)
    precondition(feedExpansion.rows.contains(key) && documentHeight() > openHeight,
                 "Clearing search must restore group and row presentation")
    let restoredHeight = documentHeight()
    for term in ["Sam", "Jordan", "no match", "", "Lee", "no match", ""] {
        state.query = term
        settle(0.025)
    }
    settle(0.5)
    precondition(abs(documentHeight() - restoredHeight) < 1,
                 "Rapid search interruptions must settle to the current results without a stale extent")
    let additionalRows = (0..<12).map { index -> Notice in
        var notice = children[0]
        notice.key = "scroll-fixture-\(index)"
        notice.groupKey = nil
        return notice
    }
    state.notices += additionalRows
    settle(0.5)
    feedScroll.contentView.scroll(to: NSPoint(x: 0, y: 48))
    feedScroll.reflectScrolledClipView(feedScroll.contentView)
    for _ in 0..<2 {
        samplePinnedTransition({ feedExpansion.row(key).wrappedValue = false }, growing: false, anchorY: 48)
        samplePinnedTransition({ feedExpansion.row(key).wrappedValue = true }, growing: true, anchorY: 48)
    }
    feedScroll.contentView.scroll(to: .zero)
    feedScroll.reflectScrolledClipView(feedScroll.contentView)
    state.notices = [children[0]]
    settle(0.5)
    precondition(feedExpansion.rows.contains(key), "Group to singleton must retain row state")
    state.notices += NotificationFixtures.make(.picture)
    settle(0.05)
    state.notices = []
    settle(0.5)
    precondition(feedExpansion.rows.isEmpty && feedExpansion.groups.isEmpty)
    precondition(feedScroll.contentView.bounds.origin.y == 0)
    feedWindow.orderOut(nil)
    print("Group, row, reorder, search, arrival, removal and interrupted feed transitions passed")
    print("Expansion identity, removal cleanup, Reduce Motion policy, interpolated scroll sizing and interruption checks passed")
}

private struct MotionFeedProbe: View {
    @ObservedObject var state: MotionProbeState
    @ObservedObject var commands: NotificationCommandController
    let expansion: NotificationExpansionState
    var showsSearch = false
    var body: some View {
        NotificationFeed(notices: state.notices, commands: commands, maximumHeight: 460,
                         search: $state.query, showsSearch: showsSearch, expansion: expansion)
            .frame(width: 340, height: 480, alignment: .top)
    }
}

func runSearchMotionChecks() {
    let state = MotionProbeState()
    state.notices = (0..<5).map { index in
        Notice(key: "search-\(index)", app: "Messages", title: index == 4 ? "Survivor" : "Other \(index)",
               body: "Search animation fixture", revision: "1", dismissible: true, postedAt: 0)
    }
    let commands = NotificationTestbed().commands
    let expansion = NotificationExpansionState()
    let host = NSHostingView(rootView: MotionFeedProbe(state: state, commands: commands, expansion: expansion, showsSearch: true))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    func settle(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
    func searchField(_ view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        return view.subviews.compactMap(searchField).first
    }
    func markers(_ view: NSView) -> [NSView] {
        if view.identifier?.rawValue == "notification-card-swipe" { return [view] }
        return view.subviews.flatMap(markers)
    }
    settle(0.4)
    let row = markers(host).max { left, right in
        left.convert(left.bounds, to: host).minY < right.convert(right.bounds, to: host).minY
    }!
    let document = row.enclosingScrollView!.documentView!
    let start = row.convert(row.bounds, to: document).minY
    let field = searchField(host)!
    window.makeFirstResponder(field)
    let editor = field.currentEditor() as! NSTextView
    editor.insertText("survivor", replacementRange: NSRange(location: 0, length: 0))
    var samples: [CGFloat] = []
    for _ in 0..<15 {
        settle(0.016)
        samples.append(row.convert(row.bounds, to: document).minY)
    }
    settle(0.4)
    let end = row.convert(row.bounds, to: document).minY
    precondition(state.query == "survivor", "Native search editing must update the feed binding")
    precondition(samples.contains { $0 > min(start, end) + 1 && $0 < max(start, end) - 1 },
                 "Search must animate surviving notification positions rather than snapping")
    editor.selectAll(nil)
    editor.deleteBackward(nil)
    var returningSamples: [CGFloat] = []
    for _ in 0..<15 {
        settle(0.016)
        returningSamples.append(row.convert(row.bounds, to: document).minY)
    }
    settle(0.4)
    precondition(state.query.isEmpty)
    precondition(returningSamples.contains { $0 > min(start, end) + 1 && $0 < max(start, end) - 1 },
                 "Clearing native search must animate notification cards back into position")
    precondition(abs(row.convert(row.bounds, to: document).minY - start) < 1)
    window.orderOut(nil)
    print("Native search editing and clearing animate notification cards across the hosting boundary")
}

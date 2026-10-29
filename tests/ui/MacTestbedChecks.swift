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
    NSApp.finishLaunching()
    let screen = NSRect(x: -1440, y: 180, width: 1440, height: 850)
    let anchor = NSRect(x: -800, y: screen.maxY, width: 30, height: 24)
    let frame = NotificationPaneLayout.frame(in: screen, anchor: anchor)
    precondition(frame.midX == anchor.midX && frame.maxY == anchor.minY - 2)
    precondition(frame.width == 444 && frame.height == 680 && screen.contains(frame), "Pane must fit secondary screens with negative origins")
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
    let statusButton = controller.statusButtonForChecks
    func checkHighlight(_ expected: Bool, _ context: String) {
        // On macOS 27+, actual menu-bar input owns an AppKit expanded session.
        // Programmatic pane checks do not enter that system tracking session.
        if #available(macOS 27.0, *) { return }
        let actual = statusButton.cell?.isHighlighted == true
        if actual != expected {
            fputs("Status highlight failure (\(context)): expected \(expected), got \(actual)\n", stderr)
            fatalError("Incorrect status button highlight")
        }
    }
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
    controller.show()
    settle()
    let panel = NSApp.windows.compactMap { $0 as? NotificationPanel }.first!
    precondition(panel.isVisible && !panel.isOpaque && !panel.hasShadow)
    checkHighlight(true, "opening")
    precondition(panel.styleMask.contains(.nonactivatingPanel) && !panel.styleMask.contains(.titled))
    let surface = panel.contentView as! NotificationPaneSurface
    precondition(surface.compositor.window === panel && surface.host.window === panel,
                 "A single pane window must own backdrop input and notification content")
    precondition(panel.childWindows?.isEmpty != false,
                 "The pane must not create a click-through backdrop window")
    precondition(surface.backdrop.material == .underWindowBackground)
    precondition(surface.backdrop.blendingMode == .behindWindow && surface.backdrop.layer?.mask != nil)
    if (26...27).contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        precondition(surface.compositor.isAvailable, "The tested OS must provide a native backdrop")
    }
    if surface.compositor.isAvailable && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
        precondition(!surface.compositor.isHidden && surface.backdrop.isHidden,
                     "Use the blur-only renderer when available")
        precondition(surface.compositor.maskImage != nil && surface.compositor.frame == surface.backdrop.frame,
                     "Real blur must share the localized, feathered bounds")
        func kernel(_ view: CompositorBackdrop) -> Double? {
            let gaussian = view.blurLayer?.filters?.compactMap { $0 as? NSObject }.first {
                $0.value(forKey: "type") as? String == "gaussianBlur"
            }
            return (gaussian?.value(forKey: "inputRadius") as? NSNumber)?.doubleValue
        }
        precondition(kernel(surface.compositor) == 3,
                     "The backdrop must always use the default blur")
        precondition(panel.value(forKey: "shouldAutoFlattenLayerTree") as? Bool == false,
                     "Idle windows must retain live behind-window sampling")
        precondition(surface.compositor.blurLayer!.value(forKey: "groupName") as? String != "NSCGSWindowBehindWindowCaptureBackdropGroup",
                     "Backdrop filtering must not share the notification materials' capture group")
        let blur = surface.compositor.blurLayer!
        precondition(blur.value(forKey: "windowServerAware") as? Bool == true,
                     "The blur must sample behind the window")
        precondition(surface.host.layer?.filters?.isEmpty != false,
                     "The notification host must never receive a blur filter")
    }
    let originalAppearance = surface.appearance
    for system in [NSAppearance.Name.aqua, .darkAqua] {
        surface.appearance = NSAppearance(named: system)
        settle()
        precondition(surface.backdrop.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                     "Backdrop must remain dark in both system appearances")
        let expected: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.16
        precondition(abs(surface.backdrop.alphaValue - expected) < 0.001)
        precondition(surface.host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == system)
    }
    surface.setContentHeight(120)
    surface.layoutSubtreeIfNeeded()
    precondition(surface.backdrop.frame.height == 186, "A short list must not leave a panel-sized backdrop")
    precondition(surface.compositor.frame.maxY == surface.bounds.maxY,
                 "A short backdrop must stay anchored beneath the menu bar")
    precondition(surface.compositor.layer?.frame == surface.compositor.frame,
                 "The compositor root must retain AppKit's position when the backdrop shrinks")
    let maskTemplate = surface.backdropMaskImage
    let maskPixels = NSBitmapImageRep(cgImage: maskTemplate!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    let middleY = maskPixels.pixelsHigh / 2
    precondition(maskPixels.colorAt(x: 0, y: middleY)!.alphaComponent == 0 &&
                 maskPixels.colorAt(x: maskPixels.pixelsWide - 1, y: middleY)!.alphaComponent == 0,
                 "Backdrop must reach full transparency before its window edge")
    precondition(maskPixels.colorAt(x: 12, y: middleY)!.alphaComponent < 0.02,
                 "The outer feather must ease in gently over a bright desktop")
    precondition(maskPixels.colorAt(x: 24, y: 24)!.alphaComponent == 0,
                 "Rounded falloff must clear the corners instead of outlining a rectangle")
    precondition(surface.subviews.filter { $0 !== surface.host && $0.layer?.backgroundColor != nil }
        .allSatisfy { $0.layer?.mask?.contentsScale == 1 },
                 "Wash and input masks must preserve their point-sized feather on Retina displays")
    surface.setContentHeight(300)
    surface.layoutSubtreeIfNeeded()
    precondition(surface.backdrop.frame.height == 366, "Backdrop must follow visible content height")
    precondition(surface.backdropMaskImage === maskTemplate,
                 "Animated backdrop resizing must reuse its feathered image template")
    surface.appearance = originalAppearance
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
    settle()
    precondition(!panel.isVisible, "Escape must close the pane")
    checkHighlight(false, "Escape")
    controller.show()
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
    controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
    precondition(panel.isVisible, "Native menu tracking must not dismiss the pane")
    NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
    precondition(panel.contentView === surface, "Reopening must preserve presentation state")
    if #unavailable(macOS 27.0) {
        statusButton.performClick(nil)
        settle()
        precondition(!panel.isVisible, "Menu-bar toggle must close the pane")
        checkHighlight(false, "button close")
        statusButton.performClick(nil)
        settle()
        precondition(panel.isVisible, "Menu-bar toggle must reopen the pane")
        checkHighlight(true, "button reopen")
    }
    controller.hide()
    controller.show()
    settle()
    precondition(panel.isVisible && panel.alphaValue == 1,
                 "An old animation completion must not hide a newly shown pane")
    func clickEvent(in window: NSWindow, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }
    let buttonPoint = statusButton.convert(NSPoint(x: statusButton.bounds.midX, y: statusButton.bounds.midY), to: nil)
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
    let consumedStatusClick = controller.handleDismissalMouseDown(clickEvent(in: statusButton.window!, at: buttonPoint))
    if #available(macOS 27.0, *) {
        precondition(!consumedStatusClick && panel.isVisible,
                     "Status-item clicks must reach AppKit without cancelling its native session")
        precondition(statusButton.action == nil, "Native sessions must own the status item without a custom toggle")
        controller.hide()
    } else {
        precondition(consumedStatusClick, "Legacy closing clicks must not also activate the button")
    }
    settle()
    precondition(!panel.isVisible)
    NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
    controller.show()
    surface.setContentHeight(120)
    let content = surface.contentFrame
    precondition(content.width == NotificationPaneLayout.contentWidth && content.height == 120)
    let inside = NSPoint(x: content.midX, y: content.midY)
    precondition(!controller.handleDismissalMouseDown(clickEvent(in: panel, at: surface.convert(inside, to: nil))) && panel.isVisible,
                 "Clicks inside visible content must reach its controls")
    for point in [NSPoint(x: content.minX - 1, y: content.midY),
                  NSPoint(x: content.maxX + 1, y: content.midY),
                  NSPoint(x: content.midX, y: content.minY - 1),
                  NSPoint(x: content.midX, y: surface.bounds.minY + 1)] {
        precondition(controller.handleDismissalMouseDown(clickEvent(in: panel, at: surface.convert(point, to: nil))),
                     "Side blur, bottom feather, and the unused window tail must dismiss the pane")
        settle()
        precondition(!panel.isVisible)
        controller.show()
        surface.setContentHeight(120)
    }
    let other = NSWindow(contentRect: NSRect(x: 10, y: 10, width: 100, height: 100),
                         styleMask: [.titled], backing: .buffered, defer: false)
    other.makeKeyAndOrderFront(nil)
    settle()
    precondition(!panel.isVisible, "Moving focus to another window must close the pane")
    checkHighlight(false, "focus dismissal")
    other.orderOut(nil)
    controller.show()
    NotificationCenter.default.post(name: .init("PhoneCheckShow"), object: nil)
    settle()
    precondition(panel.isVisible, "Banner actions must reveal the same pane")
    controller.hide()
    settle()
    if (26...27).contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
       !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
        let probe = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        probe.isOpaque = false; probe.backgroundColor = .clear
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        let nested = NotificationPaneSurface(frame: NSRect(x: 20, y: 20, width: 444, height: 460), root: AnyView(Color.clear))
        container.addSubview(nested)
        probe.contentView = container
        probe.orderFront(nil)
        settle()
        precondition(nested.compositor.isAvailable && !nested.compositor.isHidden && nested.compositor.blurLayer != nil,
                     "The backdrop must remain available when attached beneath another view")
        probe.orderOut(nil)
    }
    print("Pane geometry, blur, scrolling, animated dismissal, content hit regions, menu toggle, and reopening checks passed")
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
    var usesInternalSearch = false
    var body: some View {
        NotificationFeed(notices: state.notices, commands: commands, maximumHeight: 460,
                         search: usesInternalSearch ? nil : $state.query, showsSearch: showsSearch, expansion: expansion)
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
    let host = NSHostingView(rootView: MotionFeedProbe(state: state, commands: commands, expansion: expansion, showsSearch: true, usesInternalSearch: true)
        .background(Color.white).environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    func settle(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
    func render(_ name: String) -> NSBitmapImageRep {
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if CommandLine.arguments.contains("--render-search") {
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/phone-check-search-\(name).png"))
        }
        return bitmap
    }
    // Measure visible ink in the outgoing card, over an opaque fixture background.
    // A moving invisible native probe cannot satisfy this rendering assertion.
    func ink(_ bitmap: NSBitmapImageRep, in rect: NSRect) -> Double {
        let scaleX = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        let top = host.isFlipped ? rect.minY : host.bounds.maxY - rect.maxY
        let minX = max(0, Int(rect.minX * scaleX))
        let maxX = min(bitmap.pixelsWide, Int(rect.maxX * scaleX))
        let minY = max(0, Int(top * scaleY))
        let maxY = min(bitmap.pixelsHigh, Int((top + rect.height) * scaleY))
        var total = 0.0
        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += 1 - (0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent)
            }
        }
        return total
    }

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
    let outgoing = markers(host).min { left, right in
        left.convert(left.bounds, to: host).minY < right.convert(right.bounds, to: host).minY
    }!
    let outgoingRect = outgoing.convert(outgoing.bounds, to: host).insetBy(dx: 10, dy: 6)
    let initialInk = ink(render("before"), in: outgoingRect)
    precondition(initialInk > 100, "The rendering fixture must contain visible outgoing card text")
    var fadingInk: Double = 0
    let field = searchField(host)!
    window.makeFirstResponder(field)
    let editor = field.currentEditor() as! NSTextView
    editor.insertText("survivor", replacementRange: NSRange(location: 0, length: 0))
    var samples: [CGFloat] = []
    for index in 0..<15 {
        settle(0.016)
        samples.append(row.convert(row.bounds, to: document).minY)
        if index == 3 { fadingInk = ink(render("during"), in: outgoingRect) }
    }
    settle(0.4)
    let end = row.convert(row.bounds, to: document).minY
    _ = render("after")
    precondition(field.stringValue == "survivor", "Native search editing must update the field")
    let remainingInk = fadingInk / initialInk
    precondition(remainingInk > 0.1 && remainingInk < 0.95,
                 "Outgoing rendered cards must fade, not disappear immediately (ink fraction \(remainingInk))")
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
    precondition(field.stringValue.isEmpty)
    precondition(returningSamples.contains { $0 > min(start, end) + 1 && $0 < max(start, end) - 1 },
                 "Clearing native search must animate notification cards back into position")
    precondition(abs(row.convert(row.bounds, to: document).minY - start) < 1)
    window.orderOut(nil)
    print("Rendered outgoing cards fade (ink fraction \(remainingInk)); native search and clearing slide surviving cards")
}

// Profile fields are optional so adding the account UI cannot invalidate an existing login.
func runSettingsChecks() {
    let data = Data(#"{"uid":"fixture-user","refreshToken":"fixture-refresh"}"#.utf8)
    let decoder = JSONDecoder()
    let legacy = try! decoder.decode(CloudTokenStore.Record.self, from: data)
    precondition(legacy.uid == "fixture-user" && legacy.refreshToken == "fixture-refresh")
    precondition(legacy.displayName == nil && legacy.email == nil)
    var profile = legacy
    profile.displayName = "Alex Parker"; profile.email = "alex@example.com"
    let restored = try! decoder.decode(CloudTokenStore.Record.self, from: JSONEncoder().encode(profile))
    precondition(restored.uid == legacy.uid && restored.refreshToken == legacy.refreshToken)
    precondition(restored.displayName == "Alex Parker" && restored.email == "alex@example.com")
    print("Settings profile storage preserves existing credentials and optional identity fields")
}

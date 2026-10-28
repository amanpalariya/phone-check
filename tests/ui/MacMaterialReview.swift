import AppKit
import SwiftUI
import PhoneCheckCore

// Visual-only app. No listener, Keychain reads, permission requests, or pairing.
@main
struct MaterialReview {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--testbed-checks") {
            runTestbedChecks()
            return
        }
        if CommandLine.arguments.contains("--pane-checks") {
            runPaneChecks()
            return
        }
        if CommandLine.arguments.contains("--pane") {
            app.setActivationPolicy(.accessory)
            let testbed = NotificationTestbed()
            testbed.showAll()
            testbed.showsInPane = true
            let controller = NotificationPaneController(model: Companion(startServices: false), testbed: testbed)
            controller.show()
            withExtendedLifetime(controller) { app.run() }
            return
        }
        app.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--blur-review") || CommandLine.arguments.contains("--pane-blur-review") {
            runBlurReview()
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 470),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Phone Check — Material Review"
        window.contentView = NSHostingView(rootView: Group {
            if CommandLine.arguments.contains("--testbed") { NotificationTestbedView() }
            else if CommandLine.arguments.contains("--setup") { Review() } else { RichReview() }
        })
        if let flag = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > flag + 1 {
            window.setContentSize(NSSize(width: 840, height: 740))
            window.contentView?.layoutSubtreeIfNeeded()
            // Render this fixture's view hierarchy, without capturing the desktop.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            func verifyScrollLayout(_ view: NSView) {
                if let scroll = view as? NSScrollView {
                    let width = scroll.contentView.bounds.width
                    if scroll is NotificationOverlayScrollView {
                        scroll.scrollerStyle = .legacy
                        scroll.layoutSubtreeIfNeeded()
                        precondition(scroll.scrollerStyle == .overlay, "Feed must preserve overlay scrolling")
                        precondition(abs(scroll.contentView.bounds.width - scroll.bounds.width) < 1, "No trailing scrollbar gutter")
                        precondition(abs(scroll.contentView.bounds.width - width) < 1, "Scrollbar must not resize rows")
                        if CommandLine.arguments.contains("--long-reply") {
                            precondition((scroll.documentView?.frame.height ?? 0) > 1000, "Expanded long text must contribute its full scroll height")
                        }
                    }
                    precondition((scroll.documentView?.frame.width ?? 0) <= width + 1, "No horizontal overflow")
                    if CommandLine.arguments.contains("--bottom"), let document = scroll.documentView {
                        let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
                        document.scroll(NSPoint(x: 0, y: bottom))
                        precondition(abs(scroll.contentView.bounds.maxY - document.frame.height) < 1 || bottom == 0,
                                     "The end of expanded content must be reachable")
                    }
                }
                for child in view.subviews { verifyScrollLayout(child) }
            }
            if let view = window.contentView { verifyScrollLayout(view) }
            print("Native scrolling and horizontal-overflow layout checks passed")
            window.contentView?.layoutSubtreeIfNeeded()
            if let view = window.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
            }
            return
        }
        if let screen = NSScreen.main { window.setFrame(screen.visibleFrame, display: true) }
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(window) { app.run() }
    }
}

private struct Review: View {
    @StateObject private var model = Companion(startServices: false)
    var body: some View {
        if #available(macOS 26.0, *) {
            ZStack {
                LinearGradient(colors: [.blue, .cyan, .orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 28) {
                    VStack(spacing: 14) {
                        Text("Regular · Light").font(.headline).foregroundStyle(.white)
                        CompanionView(model: model).environment(\.colorScheme, .light)
                    }
                    VStack(spacing: 14) {
                        Text("Regular · Dark").font(.headline).foregroundStyle(.white)
                        CompanionView(model: model).environment(\.colorScheme, .dark)
                    }
                }.padding(36)
            }.frame(minWidth: 820, maxWidth: .infinity, minHeight: 470, maxHeight: .infinity)
        } else {
            Text("This check requires macOS 26 or later.").padding()
        }
    }
}

private struct RichReview: View {
    @StateObject private var companion = Companion(startServices: false)
    @StateObject private var testbed = NotificationTestbed()
    @StateObject private var commands = NotificationCommandController(current: { _ in nil }, connected: { false }, send: { _ in })
    private let notices: [Notice] = {
        let json = #"[{"key":"chat","app":"Messages","title":"Weekend plans","body":"","revision":"1","dismissible":true,"postedAt":1,"kind":"messaging","messages":[{"sender":"Alex","text":"Coffee at 10?","time":1793075400000,"attachment":false},{"sender":"Sam","text":"See you there.","time":1793075460000,"attachment":false}],"actions":[{"id":"reply","title":"Reply","input":true,"freeform":true,"choices":["Yes","Later"],"enabled":true,"requiresUnlock":false,"destructive":false}],"openable":true},{"key":"progress","app":"Downloads","title":"Downloading update","body":"System update","revision":"2","dismissible":false,"postedAt":2,"kind":"progress","ongoing":true,"progress":{"value":75,"max":100,"indeterminate":false}},{"key":"media","app":"Music","title":"Morning playlist","body":"Sample artist","revision":"3","dismissible":true,"postedAt":3,"kind":"media","actions":[{"id":"pause","title":"Pause","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false},{"id":"next","title":"Next","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false}]}]"#
        var result = try! JSONDecoder().decode([Notice].self, from: Data(json.utf8))
        let read = #"{"id":"read","title":"Mark as read","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false}"#
        result[0].actions?.append(try! JSONDecoder().decode(NoticeAction.self, from: Data(read.utf8)))
        let call = #"{"key":"call","app":"Phone","title":"Alex Morgan","body":"Incoming call","revision":"1","dismissible":false,"postedAt":4,"kind":"call","actions":[{"id":"decline","title":"Decline","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":true},{"id":"answer","title":"Answer","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false}]}"#
        result.insert(try! JSONDecoder().decode(Notice.self, from: Data(call.utf8)), at: 0)
        // Deterministic artwork exercises the same bounded JPEG decoder as the phone.
        let art = NSImage(size: NSSize(width: 160, height: 160), flipped: false) { rect in
            NSGradient(starting: .systemIndigo, ending: .systemOrange)!.draw(in: rect, angle: 45)
            NSColor.white.withAlphaComponent(0.4).setFill()
            NSBezierPath(ovalIn: NSRect(x: 44, y: 44, width: 72, height: 72)).fill()
            return true
        }
        let jpeg = NSBitmapImageRep(data: art.tiffRepresentation!)!.representation(using: .jpeg, properties: [.compressionFactor: 0.7])!
        result[result.count - 1].image = jpeg.base64EncodedString()
        var groupSummary = result[1]
        groupSummary.key = "inbox-summary"; groupSummary.app = "Mail"; groupSummary.title = "2 new messages"
        groupSummary.groupKey = "inbox"; groupSummary.groupSummary = true
        groupSummary.actions = result[1].actions; groupSummary.messages = nil; groupSummary.openable = true
        result.append(groupSummary)
        for (index, sender) in ["Jordan Lee", "Design team"].enumerated() {
            var child = groupSummary
            child.key = "inbox-\(index)"; child.groupSummary = false
            child.actions = result[1].actions
            child.title = sender; child.body = index == 0 ? "The updated sketches are ready to review." : "Friday's catch-up is at 3."
            result.append(child)
        }
        if CommandLine.arguments.contains("--stress") {
            var long = result[1]
            long.key = "long"; long.app = "A very long application name"; long.title = "A long notification title that needs room to wrap without pushing its controls out of reach"
            long.messages = nil
            long.body = "First line\nSecond line\nThird line\nFourth line\n" + String(repeating: "Long notification content. ", count: 80)
            result.insert(long, at: 0)
            var disabled = result[0]
            disabled.key = "disabled"; disabled.title = "Action available on phone"
            disabled.body = "This notification needs an attachment."
            if disabled.actions?.isEmpty == false { disabled.actions![0].enabled = false }
            result.append(disabled)
            var summary = result[1]
            summary.key = "summary"; summary.app = "Mail"; summary.title = "2 new messages"
            summary.groupKey = "mail"; summary.groupSummary = true; summary.actions = []
            result.append(summary)
            for index in 1...2 {
                var child = summary
                child.key = "mail-\(index)"; child.groupSummary = false; child.title = "Message \(index)"
                child.body = "A grouped message preview."; result.append(child)
            }
        }
        return result
    }()
    var body: some View {
        HStack(spacing: 24) {
            pane.environment(\.colorScheme, .light)
            pane.environment(\.colorScheme, .dark)
        }.padding(24).background(LinearGradient(colors: [.blue, .cyan, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            .onAppear {
                if CommandLine.arguments.contains("--testbed-popover") {
                    testbed.showAll()
                    testbed.showsInPane = true
                }
                if CommandLine.arguments.contains("--companion") { companion.showPreview(notices) }
                let key = CommandLine.arguments.contains("--long-reply") ? "long" : CommandLine.arguments.contains("--summary-reply") ? "inbox-summary" : CommandLine.arguments.contains("--group-reply") ? "inbox-0" : "chat"
                if ["--reply", "--group-reply", "--long-reply", "--summary-reply", "--details"].contains(where: CommandLine.arguments.contains),
                   let notice = notices.first(where: { $0.key == key }), let action = notice.actions?.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        commands.beginReply(notice, action: action)
                        if CommandLine.arguments.contains("--details") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { commands.replyTarget = nil }
                        }
                    }
                }
            }
    }
    private var pane: some View {
        Group {
            if CommandLine.arguments.contains("--testbed-popover") {
                VStack {
                    CompanionView(model: companion, testbed: testbed)
                    Spacer(minLength: 0)
                }
            } else if CommandLine.arguments.contains("--companion") {
                VStack {
                    CompanionView(model: companion)
                    Spacer(minLength: 0)
                }
            } else if CommandLine.arguments.contains("--expanded") {
                ScrollView(.vertical) {
                    VStack(spacing: 8) {
                        ForEach(notices.filter { $0.groupKey == nil }) {
                            RichNoticeRow(notice: $0, commands: commands, initiallyExpanded: true)
                        }
                    }.padding(10)
                }
            } else {
                VStack {
                    NotificationFeed(notices: notices, commands: commands)
                    Spacer(minLength: 0)
                }
            }
        }
            .environment(\.appearsActive, true).environment(\.controlActiveState, .key)
            .frame(width: 340, height: 680)
    }
}


// Separate windows are essential: the material must sample pixels BEHIND the window.
private func runBlurReview() {
    let backdrop = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
    backdrop.title = "Backdrop material comparison"
    backdrop.contentView = BlurReviewPattern(frame: NSRect(x: 0, y: 0, width: 920, height: 600))
    backdrop.center()
    backdrop.makeKeyAndOrderFront(nil)
    let frame = backdrop.convertToScreen(NSRect(x: 0, y: 0, width: 920, height: 600))
    let samples = NotificationPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    samples.title = "Blur material samples"
    samples.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
    samples.isOpaque = false
    samples.backgroundColor = .clear
    samples.hasShadow = false
    let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
    let materials: [(String, NSVisualEffectView.Material)] = [
        ("Sidebar", .sidebar), ("Under window", .underWindowBackground),
        ("Glass regular", .hudWindow), ("Glass clear", .fullScreenUI)
    ]
    if CommandLine.arguments.contains("--pane-blur-review") {
        let testbed = NotificationTestbed()
        testbed.show(.text)
        testbed.show(.messaging)
        testbed.show(.group)
        testbed.showsInPane = true
        let surface = NotificationPaneSurface(frame: NSRect(x: 266, y: 10, width: 388, height: 580),
            root: AnyView(CompanionView(model: Companion(startServices: false), testbed: testbed,
                                       feedMaximumHeight: 390)
                .padding(.top, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)))
        content.addSubview(surface)
    } else {
        for (index, sample) in materials.enumerated() {
            let effect = NSVisualEffectView(frame: NSRect(x: 20 + index * 225, y: 70, width: 205, height: 430))
            effect.material = sample.1
            effect.blendingMode = .behindWindow
            effect.state = .active
            if #available(macOS 26.0, *), index >= 2 {
                let glass = NSGlassEffectView(frame: effect.frame)
                glass.style = index == 2 ? .regular : .clear
                content.addSubview(glass)
            } else {
                content.addSubview(effect)
            }
            let label = NSTextField(labelWithString: sample.0)
            label.font = .boldSystemFont(ofSize: 20)
            label.frame = NSRect(x: 30 + index * 225, y: 520, width: 205, height: 30)
            content.addSubview(label)
        }
    }
    samples.contentView = content
    backdrop.addChildWindow(samples, ordered: .above)
    samples.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    withExtendedLifetime((backdrop, samples)) { NSApp.run() }
}

private final class BlurReviewPattern: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: .systemBlue, ending: .systemOrange)!.draw(in: bounds, angle: 20)
        for row in 0..<20 {
            let y = CGFloat(row * 30)
            let text = "Background detail · 0123456789 · sharp letters · "
            (String(repeating: text, count: 4) as NSString).draw(at: NSPoint(x: 0, y: y),
                withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
        }
    }
}

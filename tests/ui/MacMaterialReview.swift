import AppKit
import SwiftUI
import PhoneCheckCore

// Visual-only app. No listener, Keychain reads, permission requests, or pairing.
@main
struct MaterialReview {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 470),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Phone Check — Material Review"
        window.contentView = NSHostingView(rootView: Group {
            if CommandLine.arguments.contains("--setup") { Review() } else { RichReview() }
        })
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
                        MenuSurface(model: model).environment(\.colorScheme, .light)
                    }
                    VStack(spacing: 14) {
                        Text("Regular · Dark").font(.headline).foregroundStyle(.white)
                        MenuSurface(model: model).environment(\.colorScheme, .dark)
                    }
                }.padding(36)
            }.frame(minWidth: 820, maxWidth: .infinity, minHeight: 470, maxHeight: .infinity)
        } else {
            Text("This check requires macOS 26 or later.").padding()
        }
    }
}

private struct RichReview: View {
    @StateObject private var commands = NotificationCommandController(current: { _ in nil }, connected: { false }, send: { _ in })
    private let notices: [Notice] = {
        let json = #"[{"key":"chat","app":"Messages","title":"Weekend plans","body":"","revision":"1","dismissible":true,"postedAt":1,"kind":"messaging","messages":[{"sender":"Alex","text":"Coffee at 10?","time":1793075400000,"attachment":false},{"sender":"Sam","text":"See you there.","time":1793075460000,"attachment":false}],"actions":[{"id":"reply","title":"Reply","input":true,"freeform":true,"choices":["Yes","Later"],"enabled":true,"requiresUnlock":false,"destructive":false}],"openable":true},{"key":"progress","app":"Downloads","title":"Downloading update","body":"System update","revision":"2","dismissible":false,"postedAt":2,"kind":"progress","ongoing":true,"progress":{"value":75,"max":100,"indeterminate":false}},{"key":"media","app":"Music","title":"Morning playlist","body":"Sample artist","revision":"3","dismissible":true,"postedAt":3,"kind":"media","actions":[{"id":"pause","title":"Pause","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false},{"id":"next","title":"Next","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false}]}]"#
        return try! JSONDecoder().decode([Notice].self, from: Data(json.utf8))
    }()
    var body: some View {
        HStack(spacing: 24) {
            pane.environment(\.colorScheme, .light)
            pane.environment(\.colorScheme, .dark)
        }.padding(24).background(LinearGradient(colors: [.blue, .cyan, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    private var pane: some View {
        ScrollView { NotificationList(notices: notices, commands: commands) }
            .frame(width: 360, height: 650).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

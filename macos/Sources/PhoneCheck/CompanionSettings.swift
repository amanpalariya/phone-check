import AppKit
import SwiftUI

enum SettingsSection: String { case general, advanced }

/// A native preferences toolbar, independent of the transient notification pane.
final class CompanionSettingsController {
    let window: NSWindow
    private let tabs: NSTabViewController

    init(model: Companion, showPairing: @escaping () -> Void = {}, showTestbed: @escaping () -> Void = {}) {
        let tabController = NSTabViewController()
        tabs = tabController
        tabs.tabStyle = .toolbar
        tabs.title = "Phone Check Settings"
        func add<Content: View>(_ section: SettingsSection, title: String, symbol: String, content: Content) {
            let controller = NSHostingController(rootView: content)
            controller.preferredContentSize = NSSize(width: 560, height: 400)
            let item = NSTabViewItem(viewController: controller)
            item.identifier = section.rawValue; item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabController.addTabViewItem(item)
        }
        add(.general, title: "General", symbol: "gearshape", content: GeneralSettingsView(model: model, showPairing: showPairing))
        #if DEBUG
        add(.advanced, title: "Advanced", symbol: "gearshape.2",
            content: AdvancedSettingsView(showTestbed: showTestbed))
        #endif
        window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "Phone Check Settings"
        window.toolbarStyle = .preference
        window.toolbar?.displayMode = .iconAndLabel
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 400))
        window.setFrameAutosaveName("PhoneCheckSettings")
        window.center()
    }
    func select(_ section: SettingsSection) {
        if let index = tabs.tabViewItems.firstIndex(where: { $0.identifier as? String == section.rawValue }) {
            tabs.selectedTabViewItemIndex = index
        }
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct GeneralSettingsView: View {
    private static let appIcon = Bundle.main.url(forResource: "PhoneCheck", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 48, height: 48))
    @ObservedObject var model: Companion
    var showPairing: () -> Void
    var body: some View {
        SettingsPage {
            HStack(spacing: 14) {
                Image(nsImage: Self.appIcon).resizable().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Check").font(.title2.weight(.semibold))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 4)
            GroupBox {
                VStack(spacing: 0) {
                    AccountSettingsRow(model: model)
                    Divider().padding(.leading, 62)
                    PhoneSettingsRow(model: model, showPairing: showPairing)
                }
            }
            if !model.alertsAllowed {
                GroupBox {
                    HStack(spacing: 14) {
                        SettingsSymbol(name: "bell.badge", color: .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mac notifications").font(.body.weight(.medium))
                            Text("Allow alerts for new phone notifications.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button("Enable…", action: model.allowAlerts)
                    }.padding(12)
                }
            }
            Label("Notification content is encrypted between your devices.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
        }
        .onAppear { model.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAuthorization()
        }
    }
}

private final class SettingsConfirmation: ObservableObject {
    @Published var showing = false
}

private struct AccountSettingsRow: View {
    @ObservedObject var model: Companion
    @ObservedObject private var account = CloudAccount.shared
    @StateObject private var confirmation = SettingsConfirmation()
    private var name: String { account.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Google account" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                SettingsSymbol(name: "person.crop.circle", color: .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.signedIn ? name : "Google account").font(.body.weight(.medium))
                        .textSelection(.enabled)
                    Text(account.signedIn ? account.email ?? "Signed in with Google" : "Optional for syncing away from your local network.")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 12)
                if account.signedIn {
                    Button("Sign Out…") { confirmation.showing = true }
                } else {
                    Button(account.busy ? "Signing in…" : "Sign in with Google", action: account.signIn)
                        .disabled(account.busy || !account.configured)
                }
            }
            if let error = account.error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
        }
        .padding(12)
        .task { await account.refreshProfile() }
        .onChange(of: account.signedIn) { _, signedIn in
            if signedIn { Task { await account.refreshProfile() } }
        }
        .alert("Sign out of Phone Check?", isPresented: $confirmation.showing) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive, action: model.signOut)
        } message: { Text("Cloud sync will stop. Local-only pairing stays connected.") }
    }
}

private struct PhoneSettingsRow: View {
    @ObservedObject var model: Companion
    var showPairing: () -> Void
    @StateObject private var confirmation = SettingsConfirmation()
    private var connectionStatus: String {
        guard model.connected else { return model.status }
        switch model.connectionRoute {
        case .local: return "Connected over local network"
        case .cloud: return "Connected over cloud"
        case nil: return model.status
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SettingsSymbol(name: "smartphone", color: .purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.paired ? model.phoneName ?? "Android phone" : "Pair your phone")
                        .font(.body.weight(.medium)).textSelection(.enabled)
                    Text(model.paired ? connectionStatus : "Open Phone Check on Android to get started.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if model.paired { Button("Unpair…") { confirmation.showing = true } }
                else { Button("Pair Phone…", action: showPairing).buttonStyle(.borderedProminent) }
            }
            if model.paired && !model.connected {
                HStack {
                    Text("Make sure both devices are online.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Reconnect", action: model.startListening)
                }.font(.callout).padding(.leading, 52)
            }
        }
        .padding(12)
        .alert("Unpair this phone?", isPresented: $confirmation.showing) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive, action: model.unpair)
        } message: { Text("Notifications will stop syncing. You can pair again anytime.") }
    }
}

private struct SettingsSymbol: View {
    var name: String
    var color: Color = .accentColor
    var body: some View {
        Image(systemName: name).font(.system(size: 20, weight: .regular))
            .foregroundStyle(.white).frame(width: 34, height: 34)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

#if DEBUG
private struct AdvancedSettingsView: View {
    var showTestbed: () -> Void
    var body: some View {
        SettingsPage {
            GroupBox {
                HStack(spacing: 14) {
                    SettingsSymbol(name: "bell.badge")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification testbed").font(.body.weight(.medium))
                        Text("Try sample notifications and actions.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Open…", action: showTestbed).accessibilityLabel("Open notification testbed")
                }.padding(12)
            }
        }
    }
}
#endif

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

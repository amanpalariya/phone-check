import AppKit
import SwiftUI

enum SettingsSection: String { case general, account, devices, advanced }

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
            controller.preferredContentSize = NSSize(width: 560, height: 460)
            let item = NSTabViewItem(viewController: controller)
            item.identifier = section.rawValue; item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabController.addTabViewItem(item)
        }
        add(.general, title: "General", symbol: "gearshape", content: GeneralSettingsView(model: model))
        add(.account, title: "Account", symbol: "person.crop.circle", content: AccountSettingsView(model: model))
        add(.devices, title: "Devices", symbol: "laptopcomputer.and.iphone",
            content: PhoneSettingsView(model: model, showPairing: showPairing))
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
        window.setContentSize(NSSize(width: 560, height: 460))
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
    @ObservedObject var model: Companion
    var body: some View {
        SettingsPage {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Check").font(.title2.weight(.semibold))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 4)
            GroupBox {
                HStack(spacing: 14) {
                    SettingsSymbol(name: "bell.badge")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mac notifications").font(.body.weight(.medium))
                        Text(model.alertsAllowed ? "Notifications are allowed." : "Show alerts for new phone notifications.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(model.alertsAllowed ? "Open Settings…" : "Enable…") {
                        if model.alertsAllowed { model.openNotificationSettings() } else { model.allowAlerts() }
                    }
                }.padding(12)
            }
            Label("Notification content is encrypted between your devices.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
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

private struct AccountSettingsView: View {
    @ObservedObject var model: Companion
    @ObservedObject private var account = CloudAccount.shared
    @StateObject private var confirmation = SettingsConfirmation()
    private var name: String { account.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Google account" }
    private var initials: String {
        guard let name = account.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    var body: some View {
        SettingsPage {
            GroupBox {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(Color.primary.opacity(0.08))
                        if initials.isEmpty { Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(.secondary) }
                        else { Text(initials).font(.system(size: 36, weight: .medium)).foregroundStyle(.primary) }
                    }
                    .frame(width: 104, height: 104).accessibilityHidden(true)
                    .padding(.bottom, 18)
                    Text(account.signedIn ? name : "Sign in to Phone Check")
                        .font(.title2.weight(.semibold)).multilineTextAlignment(.center).textSelection(.enabled)
                    Text(account.signedIn ? account.email ?? "Signed in with Google" : "Sign in to sync beyond your local network.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .textSelection(.enabled).padding(.top, 5)
                    if account.signedIn {
                        Button("Sign Out…") { confirmation.showing = true }
                            .controlSize(.large).padding(.top, 22)
                    } else {
                        Button(account.busy ? "Signing in…" : "Sign in with Google", action: account.signIn)
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(account.busy || !account.configured).padding(.top, 22)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 20)
            }
            if account.signedIn {
                Text("Your name and email are managed by Google.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            if let error = account.error ?? model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
        }
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

/// The existing paired-phone controls stay on a dedicated device page.
struct PhoneSettingsView: View {
    @ObservedObject var model: Companion
    var showPairing: () -> Void = {}
    @StateObject private var confirmation = SettingsConfirmation()
    var body: some View {
        SettingsPage {
            GroupBox {
                HStack(spacing: 16) {
                    Image(systemName: "iphone").font(.system(size: 36, weight: .light))
                        .frame(width: 54, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.paired ? model.phoneName ?? "Android phone" : "Pair your phone")
                            .font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text(model.paired ? model.status : "Open Phone Check on Android.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if model.paired { Button("Unpair…") { confirmation.showing = true } }
                    else { Button("Pair Phone…", action: showPairing).buttonStyle(.borderedProminent) }
                }.padding(14)
            }
            if model.paired && !model.connected {
                HStack {
                    Text("Make sure both devices are online.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Reconnect", action: model.startListening)
                }.font(.callout)
            }
            Text(model.paired ? "Notifications and their actions sync while your devices are connected."
                 : "Scan the QR code on your Mac. Sign in on both devices for cloud sync.")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
        }
        .alert("Unpair this phone?", isPresented: $confirmation.showing) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive, action: model.unpair)
        } message: { Text("Notifications will stop syncing. You can pair again anytime.") }
    }
}

private struct SettingsSymbol: View {
    var name: String
    var body: some View {
        Image(systemName: name).font(.system(size: 20, weight: .regular))
            .foregroundStyle(.primary).frame(width: 38, height: 38)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
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

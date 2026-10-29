import AppKit
import SwiftUI

/// A persistent configuration window, independent of the transient notification pane.
final class CompanionSettingsController {
    let window: NSWindow
    private let tabs: NSTabViewController

    init(model: Companion, showTestbed: @escaping () -> Void = {}) {
        tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.title = "Phone Check Settings"
        let phone = NSTabViewItem(viewController: NSHostingController(rootView: PhoneSettingsView(model: model)))
        phone.label = "Phone"
        phone.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Phone")
        #if DEBUG
        let advanced = NSTabViewItem(viewController: NSHostingController(rootView:
            AdvancedSettingsView(showTestbed: showTestbed)))
        advanced.label = "Advanced"
        advanced.image = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: "Advanced")
        #endif
        tabs.addTabViewItem(phone)
        #if DEBUG
        tabs.addTabViewItem(advanced)
        #endif
        window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Phone Check Settings"
        window.toolbarStyle = .preference
        window.toolbar?.displayMode = .iconAndLabel
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 520))
        window.setFrameAutosaveName("PhoneCheckSettings")
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

#if DEBUG
private struct AdvancedSettingsView: View {
    var showTestbed: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Notification testbed")
                    Spacer()
                    Button("Open…", action: showTestbed)
                        .accessibilityLabel("Open notification testbed")
                }
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#endif

private final class PhoneSettingsState: ObservableObject {
    @Published var confirmsUnpair = false
}

struct PhoneSettingsView: View {
    @ObservedObject var model: Companion
    @StateObject private var state = PhoneSettingsState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: "iphone")
                            .font(.system(size: 32, weight: .light))
                            .frame(width: 52, height: 60).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.paired ? model.phoneName ?? "Android phone" : "Pair your phone")
                                .font(.title3.weight(.semibold)).textSelection(.enabled)
                            if model.paired {
                                Label(model.status, systemImage: model.connected ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text("Open Phone Check on Android.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        if model.paired {
                            Button("Unpair…") { state.confirmsUnpair = true }
                        } else if !model.pairing {
                            Button(model.listening ? "Pair phone" : "Retry connection") {
                                if model.listening { model.beginPairing() } else { model.startListening() }
                            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        }
                    }.padding(12)
                }
                if model.paired {
                    if model.phoneName == nil, let identifier = model.phoneIdentifier {
                        LabeledContent("Phone ID") {
                            Text(identifier).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if !model.connected {
                        HStack {
                            Text("Keep both devices on the same Wi-Fi.").foregroundStyle(.secondary)
                            Spacer()
                            if !model.listening {
                                Button("Retry", action: model.startListening)
                            }
                        }
                    }
                    GroupBox {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge").font(.title3).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mac notifications")
                                Text(model.alertsAllowed ? "Allowed" : "Alerts are off")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(model.alertsAllowed ? "Settings…" : "Enable…") {
                                if model.alertsAllowed { model.openNotificationSettings() }
                                else { model.allowAlerts() }
                            }
                        }.padding(12)
                    }
                } else if model.pairing {
                    pairing
                } else {
                    Text("Both devices need to be on the same Wi-Fi.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAuthorization()
        }
        .alert("Unpair this phone?", isPresented: $state.confirmsUnpair) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive, action: model.unpair)
        } message: {
            Text("Notifications will stop syncing. You can pair again anytime.")
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Scan with Phone Check on Android.").font(.headline)
                Spacer()
                Text("Expires in 5 minutes").font(.caption).foregroundStyle(.secondary)
            }
            if model.addresses.count > 1 {
                Picker("Mac address", selection: $model.host) {
                    ForEach(model.addresses, id: \.self) { Text($0).tag($0) }
                }
            }
            PairingQRCodeView(code: model.code)
                .frame(maxWidth: .infinity)
            DisclosureGroup("Enter code instead") {
                Text(model.code).font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled).lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button("Cancel", action: model.cancelPairing)
                Spacer()
                Button("Copy code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.code, forType: .string)
                }
            }
        }
    }
}

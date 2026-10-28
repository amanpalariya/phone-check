import SwiftUI
import AppKit
import PhoneCheckCore

#if !PHONECHECK_VISUAL_TEST
@main
struct PhoneCheckApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
#endif

final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var pane: NotificationPaneController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = Companion()
        let controller = NotificationPaneController(model: model, testbed: NotificationTestbed())
        pane = controller
        if !model.paired { controller.show() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pane?.show()
        return false
    }
}


private final class CompanionPresentation: ObservableObject {
    @Published var showsAppearance = false
    @Published var query = ""
}

struct CompanionView: View {
    @ObservedObject var model: Companion
    @ObservedObject var testbed = NotificationTestbed()
    var showTestbed: () -> Void = {}
    var feedMaximumHeight: CGFloat = 480
    var contentHeightChanged: (CGFloat) -> Void = { _ in }
    @StateObject private var presentation = CompanionPresentation()
    var body: some View {
        VStack(spacing: 0) {
            controlsCard
            if testbed.showsInPane {
                testbedContent
            } else if !model.paired {
                if model.pairing { pairing } else { welcome }
            } else {
                pairedContent
            }
            if !testbed.showsInPane, let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 18)
                    .textSelection(.enabled)
            }
        }
        .frame(width: 340)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: CompanionHeight.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(CompanionHeight.self, perform: contentHeightChanged)
        .tint(.accentColor)
        .onAppear { model.refreshAuthorization() }
        .onChange(of: testbed.showsInPane) { _, _ in presentation.query = "" }
        .sheet(isPresented: $presentation.showsAppearance) { NotificationAppearanceSettings() }
        .confirmationDialog("Unpair phone?", isPresented: $model.confirmUnpair) {
            Button("Unpair", role: .destructive, action: model.unpair)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            header
            if testbed.showsInPane {
                HStack {
                    Text("Testbed").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Exit") { testbed.showsInPane = false }.buttonStyle(.borderless)
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
            if showsSearch {
                NotificationSearchField(text: $presentation.query)
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background { NotificationSurface() }
        .padding(.horizontal, 10)
    }

    private var showsSearch: Bool {
        let notices = testbed.showsInPane ? testbed.notices : model.notices
        return !notices.isEmpty || !presentation.query.isEmpty
    }

    private var testbedContent: some View {
        VStack(spacing: 8) {
            if testbed.notices.isEmpty {
                Text("Add samples in the testbed.").foregroundStyle(.secondary).padding(24)
            } else {
                NotificationFeed(notices: testbed.notices, commands: testbed.commands, maximumHeight: feedMaximumHeight,
                                 search: $presentation.query, showsSearch: false)
            }
        }.padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Appearance…") { presentation.showsAppearance = true }
                Divider()
                Button("Notification testbed…") {
                    NSApp.activate(ignoringOtherApps: true)
                    showTestbed()
                }
                Divider()
                if model.paired {
                    Button("Notification settings", action: model.openNotificationSettings)
                    Divider()
                    Button("Unpair phone…") { model.confirmUnpair = true }
                    Divider()
                }
                Button("Quit Phone Check") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize().tint(.primary).help("Settings").accessibilityLabel("Settings")
            Spacer(minLength: 0)
            Text("Phone Check").font(.headline)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if testbed.showsInPane || model.connected {
                    let count = testbed.showsInPane ? NotificationSection.count(testbed.notices) : model.notificationCount
                    Text("\(count)").font(.caption).monospacedDigit()
                        .accessibilityLabel("\(count) notifications")
                }
                Circle().fill(testbed.showsInPane ? Color.orange : model.connected ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                    .help(testbed.showsInPane ? "Testbed" : model.status)
                    .accessibilityLabel(testbed.showsInPane ? "Testbed" : model.status)
            }.frame(minWidth: 28, minHeight: 28)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            deviceMark("iphone")
                .padding(.top, 24).padding(.bottom, 18)
            Text("Pair your phone").font(.title2.weight(.semibold))
            Text("Open Phone Check on Android.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 7)
            Button {
                if model.listening { model.beginPairing() } else { model.startListening() }
            } label: {
                Text(model.listening ? "Pair phone" : "Retry connection").frame(maxWidth: .infinity)
            }
            .modifier(NativePrimaryAction()).keyboardShortcut(.defaultAction)
            .padding(.top, 26)
        }
        .padding(.horizontal, 22).padding(.bottom, 24)
    }

    private var pairing: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                deviceMark("iphone", size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pairing code").font(.headline)
                    Text("Enter it on your phone.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.top, 14)
            if model.addresses.count > 1 {
                Picker("Mac address", selection: $model.host) {
                    ForEach(model.addresses, id: \.self) { Text($0).tag($0) }
                }.font(.caption)
            }
            Text(model.code)
                .font(.system(.caption, design: .monospaced)).lineSpacing(4)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.code, forType: .string)
            } label: { Label("Copy code", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                .modifier(NativePrimaryAction())
            HStack {
                Label("5-minute code", systemImage: "clock").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: model.cancelPairing).buttonStyle(.borderless)
            }.font(.caption)
        }.padding(.horizontal, 20).padding(.bottom, 22)
    }

    private var pairedContent: some View {
        VStack(spacing: 0) {
            if !model.listening {
                Button("Retry connection", action: model.startListening)
                    .modifier(NativePrimaryAction()).padding(.horizontal, 20).padding(.bottom, 12)
            }
            if !model.alertsAllowed {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge").foregroundStyle(.primary)
                    Text("Mac alerts off").font(.subheadline)
                    Spacer()
                    Button("Enable", action: model.allowAlerts).buttonStyle(.bordered).controlSize(.small)
                }
                .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if model.connected && !model.notices.isEmpty {
                NotificationFeed(notices: model.notices, commands: model.commands, maximumHeight: feedMaximumHeight,
                                 search: $presentation.query, showsSearch: false)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: model.connected ? "bell" : "wifi")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                    Text(model.connected ? "All clear" : "Waiting for phone")
                        .font(.body.weight(.medium)).foregroundStyle(.secondary)
                    if !model.connected {
                        Text("Keep both devices on the same Wi-Fi.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }

    private func deviceMark(_ symbol: String, size: CGFloat = 60) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary).frame(width: size, height: size)
            .background(Color.secondary.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

// Native styles retain system Liquid Glass, focus, pressed, and accessibility behavior.
private struct NativePrimaryAction: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}


private struct CompanionHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

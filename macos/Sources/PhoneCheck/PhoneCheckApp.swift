import SwiftUI
import AppKit
import PhoneCheckCore

#if !PHONECHECK_VISUAL_TEST
@main
struct PhoneCheckApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = CompanionAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

#endif

final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var presentation: MenuBarPresentation?
    private var model: Companion!
    private var showObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = Companion()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Phone Check")
            button.image?.isTemplate = true
            button.toolTip = "Phone Check"
            button.target = self
            button.action = #selector(togglePopover)
        }
        if let button = statusItem.button { presentation = MenuBarPresentation(model: model, anchor: button) }
        showObserver = NotificationCenter.default.addObserver(forName: .init("PhoneCheckShow"), object: nil, queue: .main) { [weak self] _ in self?.showPopover() }
        if !model.paired { DispatchQueue.main.async { self.showPopover() } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }
    @objc private func togglePopover() {
        if presentation?.isShown == true { presentation?.close() } else { showPopover() }
    }
    private func showPopover() {
        presentation?.show()
    }
}

enum Palette {
    static let controlAccent = Color(red: 0.45, green: 0.28, blue: 0.79)
    static let purple = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.78, green: 0.68, blue: 1, alpha: 1)
        }
        return NSColor(srgbRed: 0.45, green: 0.28, blue: 0.79, alpha: 1)
    })
}

struct CompanionView: View {
    @ObservedObject var model: Companion
    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.paired {
                if model.pairing { pairing } else { welcome }
            } else {
                pairedContent
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 18)
                    .textSelection(.enabled)
            }
        }
        .frame(width: 336)
        .tint(Palette.controlAccent)
        .onAppear { model.refreshAuthorization() }
        .confirmationDialog("Unpair phone?", isPresented: $model.confirmUnpair) {
            Button("Unpair", role: .destructive, action: model.unpair)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
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
            Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6).frame(width: 28, height: 28)
                .help(model.status).accessibilityLabel(model.status)
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
                Button("Cancel", action: model.cancelPairing).buttonStyle(.plain)
            }.font(.caption)
        }.padding(.horizontal, 20).padding(.bottom, 22)
    }

    private var pairedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "iphone").foregroundStyle(Palette.purple)
                Text(model.status).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if model.connected && !model.notices.isEmpty {
                    Text("\(model.notices.count)").font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)

            if !model.listening {
                Button("Retry connection", action: model.startListening)
                    .modifier(NativePrimaryAction()).padding(.horizontal, 20).padding(.bottom, 12)
            }
            if !model.alertsAllowed {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge").foregroundStyle(Palette.purple)
                    Text("Mac alerts off").font(.subheadline)
                    Spacer()
                    Button("Enable", action: model.allowAlerts).buttonStyle(.bordered).controlSize(.small)
                }
                .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if model.connected && !model.notices.isEmpty {
                ScrollView {
                    NotificationList(notices: model.notices, commands: model.commands)
                        .padding(.horizontal, 8)
                }.frame(maxHeight: 380).padding(.bottom, 10)
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
            .foregroundStyle(Palette.purple).frame(width: size, height: size)
            .background(Palette.purple.opacity(0.12), in: Circle())
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

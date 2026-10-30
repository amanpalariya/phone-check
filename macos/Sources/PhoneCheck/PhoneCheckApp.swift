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
        let controller = NotificationPaneController(model: model)
        pane = controller
        if !model.paired { controller.show() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pane?.show()
        return false
    }
}


private final class CompanionPresentation: ObservableObject {
    @Published var query = ""
}

struct CompanionView: View {
    @ObservedObject var model: Companion
    #if DEBUG
    @ObservedObject var testbed = NotificationTestbed()
    #endif
    var showSettings: () -> Void = {}
    var pointerOffset: CGFloat = 0
    var feedMaximumHeight: CGFloat = 480
    var contentHeightChanged: (CGFloat) -> Void = { _ in }
    @StateObject private var presentation = CompanionPresentation()
    var body: some View {
        VStack(spacing: 0) {
            controlsCard
            if (showsSamples || (model.paired && model.connected)) && !ordinaryNotices.isEmpty {
                NotificationFeed(notices: ordinaryNotices, commands: displayedCommands, maximumHeight: max(60, feedMaximumHeight - (mediaNotices.isEmpty ? 0 : 190)),
                                 search: $presentation.query, showsSearch: false)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: NotificationPaneLayout.contentWidth)
        .background {
            GeometryReader { proxy in
                AnimatedCompanionHeight(height: proxy.size.height)
                    .notificationMotion(value: proxy.size.height)
            }
        }
        .onPreferenceChange(CompanionHeight.self, perform: contentHeightChanged)
        .notificationMotion(value: model.pairing)
        .notificationMotion(value: model.paired)
        .notificationMotion(value: model.notices)
        .notificationMotion(value: displayedNotices)
        .tint(.accentColor)
        .onAppear { model.refreshAuthorization() }
        .onChange(of: showsSamples) { _, _ in presentation.query = "" }
    }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            header
            #if DEBUG
            if showsSamples {
                HStack {
                    Text("Testbed").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { testbed.showsInPane = false } label: {
                        Text("Exit").foregroundStyle(.primary)
                    }.buttonStyle(.borderless).tint(.primary)
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
            #endif
            if showsSamples || (model.paired && model.connected) {
                MediaShelf(notices: mediaNotices, commands: displayedCommands)
                    .padding(.horizontal, 14)
            }
            if showsSearch {
                NotificationSearchField(text: $presentation.query)
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
            if showsSamples {
                if displayedNotices.isEmpty {
                    Text("Add samples in the testbed.").foregroundStyle(.secondary).padding(24)
                }
            } else {
                if !model.paired {
                    PairingPane(model: model)
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
        }
        .padding(.top, NotificationPointerShape.height)
        .background { NotificationSurface(pointerOffset: pointerOffset) }
        .padding(.horizontal, 10)
    }

    private var showsSamples: Bool {
        #if DEBUG
        return testbed.showsInPane
        #else
        return false
        #endif
    }

    private var displayedNotices: [Notice] {
        #if DEBUG
        if showsSamples { return testbed.notices }
        #endif
        return model.notices
    }

    private var displayedCommands: NotificationCommandController {
        #if DEBUG
        if showsSamples { return testbed.commands }
        #endif
        return model.commands
    }

    private var ordinaryNotices: [Notice] { displayedNotices.filter { !$0.isMedia } }
    private var mediaNotices: [Notice] {
        displayedNotices.filter { $0.isMedia && $0.groupSummary != true }.sorted {
            if ($0.media?.playing == true) != ($1.media?.playing == true) { return $0.media?.playing == true }
            return $0.postedAt == $1.postedAt ? $0.key < $1.key : $0.postedAt > $1.postedAt
        }
    }
    private var showsSearch: Bool {
        (showsSamples || model.paired) && (!ordinaryNotices.isEmpty || !presentation.query.isEmpty)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Menu {
                    Button("Settings…", action: showSettings)
                        .keyboardShortcut(",")
                    Divider()
                    Button("Quit Phone Check") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .fixedSize().tint(.primary).help("Settings").accessibilityLabel("Settings")
                if model.paired && !showsSamples {
                    Image(systemName: model.connectionRoute == .local ? "wifi" :
                            model.connectionRoute == .cloud ? "cloud" : "wifi.slash")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 28)
                        .help(connectionDescription).accessibilityLabel(connectionDescription)
                }
            }
            .frame(width: 82, alignment: .leading)
            Spacer(minLength: 0)
            Text("Phone Check").font(.headline)
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) {
                if model.paired {
                    PhoneBatteryIndicator(battery: showsSamples ? nil : model.battery,
                                          connected: !showsSamples && model.connected,
                                          status: showsSamples ? "Testbed" : model.status)
                }
            }
            .frame(width: 82, height: 28, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var connectionDescription: String {
        switch model.connectionRoute {
        case .local: "Connected over local network"
        case .cloud: "Connected over cloud"
        case nil: model.status
        }
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
                    Button(action: model.allowAlerts) {
                        Text("Enable").foregroundStyle(.primary)
                    }.buttonStyle(.bordered).tint(.primary).controlSize(.small)
                }
                .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if !model.connected || model.notices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.connected ? "bell" : "wifi")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                    Text(model.connected ? "All clear" : "Waiting for phone")
                        .font(.body.weight(.medium)).foregroundStyle(.secondary)
                    if !model.connected {
                        Text("Make sure both devices are online.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }

}

// Native styles retain system Liquid Glass, focus, pressed, and accessibility behavior.
struct NativePrimaryAction: ViewModifier {
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

/// Emit the presented height each frame so the AppKit backdrop follows the list
/// through interrupted transitions instead of snapping to its destination.
private struct AnimatedCompanionHeight: View, Animatable {
    var height: CGFloat
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }
    var body: some View { Color.clear.preference(key: CompanionHeight.self, value: height) }
}

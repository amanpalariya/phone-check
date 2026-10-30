import AppKit
import SwiftUI
import Intents
import OSLog
import PhoneCheckCore

private final class ToastStackPresentation: ObservableObject {
    @Published var notices: [Notice] = []
    let expansion = NotificationExpansionState()
}

/// A transient stack, never a replay queue: overflow expires on its original timer.
final class NotificationToastController {
    private let allowsPreview: () -> Bool
    init(allowsPreview: @escaping () -> Bool = { NotificationToastController.focusAllowsPreview }) {
        self.allowsPreview = allowsPreview
    }
    #if PHONECHECK_VISUAL_TEST
    var isVisibleForChecks: Bool { panel?.isVisible == true }
    var isKeyForChecks: Bool { panel?.isKeyWindow == true }
    var panelForChecks: NSPanel? { panel }
    var keysForChecks: [String] { presentation.notices.map(\.key) }
    func hideForChecks(_ key: String) { hidePreview(key) }
    func expandForChecks(_ key: String, _ expanded: Bool) { presentation.expansion.row(key).wrappedValue = expanded }
    var expandedForChecks: Set<String> { presentation.expansion.rows }
    #endif
    private var panel: NotificationToastPanel?
    private var timer: Timer?
    private var presentation = ToastStackPresentation()
    private var deadlines: [String: Date] = [:]
    private var hovered = Set<String>()

    static var focusAllowsPreview: Bool {
        let focus = INFocusStatusCenter.default
        return AlertPolicy.focusAllowsPreview(authorized: focus.authorizationStatus == .authorized,
                                              isFocused: focus.focusStatus.isFocused)
    }

    func show(_ notice: Notice, anchor: NSRect, screen: NSScreen,
              commands: NotificationCommandController, open: @escaping () -> Void) {
        guard allowsPreview() else {
            let focus = INFocusStatusCenter.default
            PreviewDiagnostics.record("Focus gate (authorization=\(focus.authorizationStatus.rawValue), focused=\(String(describing: focus.focusStatus.isFocused)))")
            hide(); return
        }
        PreviewDiagnostics.record("Showing preview")
        deadlines[notice.key] = Date().addingTimeInterval(6)
        presentation.notices.removeAll { $0.key == notice.key }
        presentation.notices.insert(notice, at: 0)
        guard panel == nil else { return }
        let bounds = NotificationPaneLayout.frame(in: screen.visibleFrame, anchor: anchor)
        let frame = NSRect(x: bounds.minX, y: bounds.maxY - min(500, bounds.height), width: bounds.width, height: min(500, bounds.height))
        let panel = NotificationToastPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .popUpMenu; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.setAccessibilityLabel("New phone notifications")
        panel.hideAll = { [weak self] in self?.hideUpward() }
        let surface = NotificationPaneSurface(frame: NSRect(origin: .zero, size: frame.size), root: AnyView(EmptyView()))
        surface.host.rootView = AnyView(NotificationToastStack(presentation: presentation, expansion: presentation.expansion, commands: commands,
            maximumHeight: max(100, bounds.height - 54), open: open,
            hideAll: { [weak self] in self?.hideUpward() },
            hover: { [weak self, weak panel] key, inside in
                guard let self, let panel, self.panel === panel, presentation.notices.contains(where: { $0.key == key }) else { return }
                if inside { hovered.insert(key) }
                else { hovered.remove(key); deadlines[key] = Date().addingTimeInterval(6) }
            }, heightChanged: { [weak self, weak surface, weak panel] height in
                guard let self, let panel, self.panel === panel else { return }
                surface?.setContentHeight(height)
                let fitted = min(bounds.height, height + 54)
                guard fitted > 0, abs(panel.frame.height - fitted) > 1 else { return }
                panel.setFrame(NSRect(x: panel.frame.minX, y: bounds.maxY - fitted,
                                      width: bounds.width, height: fitted), display: true)
            })
            .padding(.top, NotificationPaneLayout.contentTopInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        panel.contentView = surface
        self.panel = panel
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 1
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak commands] _ in
            guard let self else { return }
            if !allowsPreview() { hide(); return }
            for key in Array(deadlines.keys) where commands?.pendingKeys.contains(key) == true || commands?.replyTarget?.key == key {
                deadlines[key] = Date().addingTimeInterval(6)
            }
            let expired = deadlines.filter { !self.hovered.contains($0.key) && Date() >= $0.value }.map(\.key)
            expired.forEach(hidePreview)
        }
    }

    func reconcile(_ notices: [Notice]) {
        let active = Dictionary(notices.map { ($0.key, $0.revision) }, uniquingKeysWith: { _, last in last })
        let stale = presentation.notices.filter { active[$0.key] != $0.revision }.map(\.key)
        stale.forEach { removePreview($0, animated: false) }
    }
    private func hidePreview(_ key: String) { removePreview(key, animated: true) }
    private func removePreview(_ key: String, animated: Bool) {
        guard presentation.notices.contains(where: { $0.key == key }) else { return }
        if presentation.notices.count == 1 { hide(animated: animated); return }
        deadlines.removeValue(forKey: key); hovered.remove(key)
        presentation.notices.removeAll { $0.key == key }
    }
    func hideUpward() { hide(animated: true) }
    func fadeOutForPane() { hide(animated: true, upward: false) }
    func hide(animated: Bool = false, upward: Bool = true) {
        timer?.invalidate(); timer = nil
        deadlines = [:]; hovered = []
        guard let panel else { presentation.notices = []; return }
        self.panel = nil
        panel.ignoresMouseEvents = true
        // Keep the exiting hosting tree's snapshot alive; a new arrival gets new state.
        if !animated { presentation.notices = []; panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { context in
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = reduced ? 0.12 : (upward ? 0.24 : 0.22)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if !reduced && upward {
                let height = (panel.contentView as? NotificationPaneSurface)?.contentFrame.height ?? panel.frame.height
                panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: height + 48), display: true)
            }
            panel.animator().alphaValue = 0
        } completionHandler: { panel.orderOut(nil) }
        presentation = ToastStackPresentation()
    }
    deinit { timer?.invalidate(); panel?.orderOut(nil) }
}

/// Arrival never requests key status; an explicitly clicked reply editor may accept focus.
final class NotificationToastPanel: NSPanel {
    var hideAll: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { hideAll() }
}

private final class ToastViewport: ObservableObject {
    @Published var rowsHeight: CGFloat = 70
}

private struct NotificationToastStack: View {
    @ObservedObject var presentation: ToastStackPresentation
    @ObservedObject var expansion: NotificationExpansionState
    @ObservedObject var commands: NotificationCommandController
    var maximumHeight: CGFloat
    @StateObject private var viewport = ToastViewport()
    var open: () -> Void
    var hideAll: () -> Void
    var hover: (String, Bool) -> Void
    var heightChanged: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        VStack(spacing: 0) {
            NotificationScroll(contentHeight: viewport.rowsHeight) {
                VStack(spacing: 0) {
                    ForEach(Array(presentation.notices.prefix(3))) { notice in
                        NotificationToast(notice: notice, commands: commands, expansion: expansion.row(notice.key), open: open,
                                          hide: hideAll, hover: { hover(notice.key, $0) })
                            .transition(reduced ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .background { GeometryReader { proxy in
                    Color.clear.preference(key: ToastRowsHeight.self, value: proxy.size.height)
                } }
                .onPreferenceChange(ToastRowsHeight.self) { height in
                    if height.isFinite && height > 0 { viewport.rowsHeight = height }
                }
            }
            .frame(height: min(max(60, viewport.rowsHeight), max(60, maximumHeight - (presentation.notices.count > 3 ? 80 : 44))))
            .notificationMotion(value: viewport.rowsHeight)
            if presentation.notices.count > 3 {
                Button("\(presentation.notices.count - 3) more", action: open)
                    .buttonStyle(.plain).font(.caption).padding(10)
                    .background { NotificationSurface() }.padding(.horizontal, 10).padding(.bottom, 8)
            }
            Button(action: hideAll) {
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary).frame(width: 24, height: 24)
                    .background { NotificationSurface() }
            }.buttonStyle(.plain).help("Hide previews").accessibilityLabel("Hide previews")
                .padding(.top, 2)
        }
        .frame(width: NotificationPaneLayout.contentWidth)
        .padding(.vertical, 8)
        .background { GeometryReader { proxy in
            ToastAnimatedHeight(height: proxy.size.height).notificationMotion(value: proxy.size.height)
        } }
        .onPreferenceChange(ToastHeight.self, perform: heightChanged)
        .animation(NotificationMotion.animation(reduceMotion: reduced), value: presentation.notices)
    }
}
private struct ToastAnimatedHeight: View, Animatable {
    var height: CGFloat
    var animatableData: CGFloat { get { height } set { height = newValue } }
    var body: some View { Color.clear.preference(key: ToastHeight.self, value: height) }
}

/// Same preview, padding, width, hover cross, and material as a collapsed list row.
struct NotificationToast: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    var expansion: Binding<Bool>? = nil
    var open: () -> Void
    var hide: () -> Void
    var hover: (Bool) -> Void
    var body: some View {
        RichNoticeRow(notice: notice, commands: commands, expansion: expansion, openPreview: open, swipeToDismiss: false)
        .padding(.horizontal, 4)
        .frame(width: NotificationPaneLayout.contentWidth)
        .onHover(perform: hover)
        .accessibilityAction(named: "Hide preview", hide)
        .accessibilityAction(named: "Open notifications", open)
    }
}

private struct ToastRowsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ToastHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Diagnostic reasons only: never record notification content, app identity, or keys.
enum PreviewDiagnostics {
    private static let logger = Logger(subsystem: "dev.phonecheck.mac", category: "NotificationPreview")
    static func record(_ reason: String) { logger.notice("\(reason, privacy: .public)") }
}

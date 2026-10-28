import AppKit
import SwiftUI
import PhoneCheckCore

/// Keep explicit Android groups together without hiding ungrouped notifications.
struct NotificationList: View {
    let notices: [Notice]
    @ObservedObject var commands: NotificationCommandController
    var body: some View {
        VStack(spacing: 8) {
            ForEach(sections) { section in
                if section.children.isEmpty {
                    RichNoticeRow(notice: section.notice, commands: commands)
                } else {
                    NotificationGroup(summary: section.summary, children: section.children, commands: commands)
                }
            }
        }.padding(.vertical, 4)
    }
    private var sections: [NotificationSection] { NotificationSection.sections(notices) }
}

/// Search remains available as notifications arrive and leave.
private final class FeedPresentation: ObservableObject {
    @Published var query = ""
    @Published var contentHeight: CGFloat = 100
}

struct NotificationFeed: View {
    let notices: [Notice]
    @ObservedObject var commands: NotificationCommandController
    @StateObject private var presentation = FeedPresentation()
    private var filtered: [Notice] {
        guard !presentation.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return notices }
        return notices.filter {
            [$0.app, $0.title, $0.alertText].contains { $0.localizedCaseInsensitiveContains(presentation.query.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
    var body: some View {
        VStack(spacing: 6) {
            if !notices.isEmpty || !presentation.query.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a notification", text: $presentation.query).textFieldStyle(.plain)
                        .accessibilityLabel("Find a notification")
                    if !presentation.query.isEmpty {
                        Button { presentation.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
            }
            OverlayNotificationScroll {
                VStack(spacing: 0) {
                    NotificationList(notices: filtered, commands: commands)
                    if filtered.isEmpty {
                        Text("No matching notifications").foregroundStyle(.secondary).padding(24)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 4)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: FeedHeight.self, value: proxy.size.height)
                        }
                    }
                    .onPreferenceChange(FeedHeight.self) { height in
                        if abs(presentation.contentHeight - height) > 1 { presentation.contentHeight = height }
                    }
            }
            .frame(height: min(max(60, presentation.contentHeight), max(180, min(480, (NSScreen.main?.visibleFrame.height ?? 800) - 200))))
        }
    }
}

/// An overlay scroller occupies no layout width. Keep the document pinned to the
/// clip view, so scrolling, expansion and updates never change the card width.
struct OverlayNotificationScroll<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: () -> Content
    private func hostedContent(_ context: Context) -> AnyView {
        AnyView(content()
            .environment(\.colorScheme, context.environment.colorScheme)
            .environment(\.controlActiveState, context.environment.controlActiveState)
            .environment(\.appearsActive, context.environment.appearsActive))
    }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NotificationScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let host = NSHostingView(rootView: hostedContent(context))
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            host.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? NSHostingView<AnyView>)?.rootView = hostedContent(context)
        scroll.scrollerStyle = .overlay
    }
}

private final class NotificationScrollView: NSScrollView {
    // AppKit broadcasts preference changes after the view is attached to a window.
    // Preserve this compact panel's overlay layout when that happens as well.
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
}

private struct FeedHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private final class GroupPresentation: ObservableObject {
    @Published var expanded = false
}

private struct NotificationGroup: View {
    let summary: Notice?
    let children: [Notice]
    @ObservedObject var commands: NotificationCommandController
    @StateObject private var presentation = GroupPresentation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var latest: Notice { children[0] }
    var body: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { presentation.expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if let icon = NoticeImage.icon(latest) ?? summary.flatMap({ NoticeImage.icon($0) }) {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            Image(systemName: "app.fill").foregroundStyle(Palette.purple)
                        }
                    }.frame(width: 24, height: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(latest.app).font(.caption.weight(.medium)).lineLimit(1)
                            Text("\(children.count)").font(.caption2.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            Spacer(minLength: 0)
                            Image(systemName: presentation.expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }.foregroundStyle(.secondary)
                        if !presentation.expanded {
                            if !latest.title.isEmpty {
                                Text(latest.title).font(.body.weight(.semibold)).lineLimit(1)
                            }
                            if !latest.alertText.isEmpty {
                                Text(latest.alertText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, presentation.expanded ? 0 : 6)
                .background(alignment: .bottom) {
                    if !presentation.expanded {
                        Capsule().fill(.regularMaterial)
                            .frame(height: 4).padding(.horizontal, 10)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(latest.app), \(children.count) notifications")
            .accessibilityValue(presentation.expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(presentation.expanded ? "Collapse group" : "Expand group")
            if presentation.expanded {
                if let summary, !(summary.actions ?? []).isEmpty || summary.openable == true {
                    RichNoticeRow(notice: summary, commands: commands)
                }
                ForEach(children) { RichNoticeRow(notice: $0, commands: commands) }
            }
        }
        .onChange(of: commands.replyTarget) { _, target in
            revealReply(target)
        }
        .onAppear { revealReply(commands.replyTarget) }
    }
    private func revealReply(_ target: NotificationCommandController.ReplyTarget?) {
        if let target, target.key == summary?.key || children.contains(where: { $0.key == target.key }) {
            presentation.expanded = true
        }
    }
}

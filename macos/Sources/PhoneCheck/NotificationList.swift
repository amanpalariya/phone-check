import AppKit
import SwiftUI
import PhoneCheckCore

/// Keep explicit Android groups together without hiding ungrouped notifications.
struct NotificationList: View {
    let notices: [Notice]
    @ObservedObject var commands: NotificationCommandController
    var body: some View {
        VStack(spacing: 0) {
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
                NotificationSearchField(text: $presentation.query)
                    .padding(.horizontal, 10)
            }
            NotificationScroll(contentHeight: presentation.contentHeight) {
                VStack(spacing: 0) {
                    NotificationList(notices: filtered, commands: commands)
                    if filtered.isEmpty {
                        Text("No matching notifications").foregroundStyle(.secondary).padding(24)
                    }
                }.frame(maxWidth: .infinity)
                    .padding(.horizontal, 4).padding(.vertical, 4)
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
    private var latest: Notice { children[0] }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var canDismiss: Bool {
        if let summary, summary.dismissible { return !commands.pendingKeys.contains(summary.key) }
        return children.contains { $0.dismissible && !commands.pendingKeys.contains($0.key) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation.expanded {
                HStack(spacing: 8) {
                    Text(latest.app).font(.subheadline.weight(.semibold))
                    Text("\(children.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: 0)
                    expansionButton
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .modifier(NotificationCard(canDismiss: canDismiss, dismiss: dismissGroup, surface: false))
                .contextMenu { if let summary { NotificationGroupActions(notice: summary, commands: commands) } }
                ForEach(children) { RichNoticeRow(notice: $0, commands: commands) }
                if let summary {
                    NotificationReplyComposer(notice: summary, commands: commands).padding(.horizontal, 18)
                }
            } else {
                NotificationPreview(notice: latest, count: children.count) { expansionButton }
                    .padding(10)
                    .modifier(NotificationCard(canDismiss: canDismiss, dismiss: dismissGroup))
                    .contextMenu { if let summary { NotificationGroupActions(notice: summary, commands: commands) } }
            }
            if let summary, let feedback = commands.feedback[summary.key] {
                Text(feedback).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18)
            }
        }
        .onChange(of: commands.replyTarget) { _, target in revealReply(target) }
        .onAppear { revealReply(commands.replyTarget) }
    }
    private var expansionButton: some View {
        NotificationChevron(expanded: presentation.expanded, subject: "group") {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { presentation.expanded.toggle() }
        }
    }
    private func dismissGroup() {
        if let summary, summary.dismissible { commands.dismiss(summary) }
        else { for child in children where child.dismissible { commands.dismiss(child) } }
    }
    private func revealReply(_ target: NotificationCommandController.ReplyTarget?) {
        if let target, target.key == summary?.key || children.contains(where: { $0.key == target.key }) {
            presentation.expanded = true
        }
    }
}

/// Summary capabilities belong to the group, rather than an extra notification row.
private struct NotificationGroupActions: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    private var pending: Bool { commands.pendingKeys.contains(notice.key) }
    @ViewBuilder var body: some View {
        ForEach(notice.actions ?? []) { action in
            Button(role: action.destructive ? .destructive : nil) {
                if action.input { commands.beginReply(notice, action: action) }
                else { commands.perform(notice, action: action) }
            } label: { Text(action.title.isEmpty ? "Action" : action.title) }
                .disabled(pending || !action.enabled)
        }
        if notice.openable == true {
            Button("Open on phone") { commands.open(notice) }.disabled(pending)
        }
        if notice.dismissible {
            Button("Dismiss group on phone") { commands.dismiss(notice) }.disabled(pending)
        }
    }
}

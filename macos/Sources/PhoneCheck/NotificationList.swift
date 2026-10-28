import AppKit
import SwiftUI
import PhoneCheckCore

/// Keep explicit Android groups together without hiding ungrouped notifications.
struct NotificationList: View {
    let notices: [Notice]
    @ObservedObject var commands: NotificationCommandController
    var activeNotices: [Notice]? = nil
    @StateObject private var expansion = NotificationExpansionState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(notices: [Notice], commands: NotificationCommandController, activeNotices: [Notice]? = nil,
         expansion: NotificationExpansionState = NotificationExpansionState()) {
        self.notices = notices
        self.commands = commands
        self.activeNotices = activeNotices
        _expansion = StateObject(wrappedValue: expansion)
    }

    // A single sibling collection keeps child identity stable when a group loses
    // its summary, gains members, reorders, or becomes a single notification.
    private struct Item: Identifiable {
        let id: String
        let section: NotificationSection
        var child: Notice? = nil
    }
    private var items: [Item] {
        NotificationSection.sections(notices).flatMap { section -> [Item] in
            guard !section.children.isEmpty else {
                return [Item(id: "notice:\(section.notice.key)", section: section, child: section.notice)]
            }
            let group = Item(id: section.id, section: section)
            guard expansion.groups.contains(section.id) else { return [group] }
            return [group] + section.children.map { Item(id: "notice:\($0.key)", section: section, child: $0) }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                if let child = item.child {
                    RichNoticeRow(notice: child, commands: commands, summary: item.section.children.isEmpty ? item.section.summary : nil,
                                  expansion: expansion.row(child.key))
                        .transition(NotificationMotion.transition(reduceMotion: reduceMotion))
                } else {
                    NotificationGroup(summary: item.section.summary, children: item.section.children, commands: commands,
                                      expanded: expansion.group(item.section.id))
                        .transition(NotificationMotion.transition(reduceMotion: reduceMotion))
                }
            }
        }
        .padding(.vertical, 4)
        .notificationMotion(value: notices)
        .notificationMotion(value: expansion.groups)
        .notificationMotion(value: expansion.rows)
        .notificationMotion(value: commands.replyTarget)
        .notificationMotion(value: commands.feedback)
        .notificationMotion(value: commands.pendingKeys)
        .notificationMotion(value: commands.replyDraft)
        .onChange(of: activeNotices ?? notices) { _, _ in
            expansion.retain(notices: activeNotices ?? notices)
        }
    }
}

/// Search remains available as notifications arrive and leave.
private final class FeedPresentation: ObservableObject {
    @Published var query = ""
    @Published var contentHeight: CGFloat = 100
    var measured = false
    let expansion = NotificationExpansionState()
}

struct NotificationFeed: View {
    let notices: [Notice]
    @ObservedObject var commands: NotificationCommandController
    var maximumHeight: CGFloat = 480
    var search: Binding<String>? = nil
    var showsSearch = true
    var expansion: NotificationExpansionState? = nil
    @StateObject private var presentation = FeedPresentation()
    private var query: Binding<String> { search ?? $presentation.query }
    private var filtered: [Notice] {
        let term = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return notices }
        return notices.filter {
            $0.app.localizedCaseInsensitiveContains(term) || $0.title.localizedCaseInsensitiveContains(term)
                || $0.alertText.localizedCaseInsensitiveContains(term)
        }
    }
    var body: some View {
        let visibleNotices = filtered
        return VStack(spacing: 6) {
            if showsSearch && (!notices.isEmpty || !query.wrappedValue.isEmpty) {
                NotificationSearchField(text: query)
                    .padding(.horizontal, 10)
            }
            NotificationScroll(contentHeight: presentation.contentHeight) {
                VStack(spacing: 0) {
                    NotificationList(notices: visibleNotices, commands: commands, activeNotices: notices,
                                     expansion: expansion ?? presentation.expansion)
                    if visibleNotices.isEmpty {
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
                        guard height.isFinite, height > 0 else { return }
                        if !presentation.measured {
                            presentation.measured = true
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { presentation.contentHeight = height }
                        } else if abs(presentation.contentHeight - height) > 1 {
                            presentation.contentHeight = height
                        }
                    }
            }
            .frame(height: min(max(60, presentation.contentHeight), max(60, maximumHeight)), alignment: .top)
            .notificationMotion(value: presentation.contentHeight)
            // Start semantic transitions before crossing the hosting boundary.
            // A search edit can change rows without changing the measured height.
            .notificationMotion(value: visibleNotices)
        }
    }
}

private struct FeedHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct NotificationGroup: View {
    let summary: Notice?
    let children: [Notice]
    @ObservedObject var commands: NotificationCommandController
    @Binding var expanded: Bool
    private var latest: Notice { children[0] }
    private var canDismiss: Bool {
        if let summary, summary.dismissible { return !commands.pendingKeys.contains(summary.key) }
        return children.contains { $0.dismissible && !commands.pendingKeys.contains($0.key) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                HStack(spacing: 8) {
                    Text(latest.app).font(.title3.weight(.semibold))
                    Text("\(children.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: 0)
                    expansionButton
                }
                .padding(.horizontal, 12)
                .modifier(NotificationCard(canDismiss: canDismiss, dismiss: dismissGroup, surface: false))
                .contextMenu { if let summary { NotificationGroupActions(notice: summary, commands: commands) } }
                if let summary {
                    NotificationReplyComposer(notice: summary, commands: commands).padding(.horizontal, 18)
                }
            } else {
                Button(action: toggleExpansion) {
                    NotificationPreview(notice: latest, count: children.count) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand \(latest.app) group, \(children.count) notifications")
                    .accessibilityValue("Collapsed")
                    .modifier(NotificationCard(canDismiss: canDismiss, dismiss: dismissGroup,
                                               stackDepth: min(2, children.count - 1)))
                    .contextMenu { if let summary { NotificationGroupActions(notice: summary, commands: commands) } }
            }
            if let summary, let feedback = commands.feedback[summary.key] {
                Text(feedback).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18)
            }
        }
        .padding(.top, expanded ? 16 : 0)
        .notificationMotion(value: expanded)
        .onChange(of: commands.replyTarget) { _, target in revealReply(target) }
        .onAppear { revealReply(commands.replyTarget) }
    }
    private var expansionButton: some View {
        NotificationChevron(expanded: expanded, subject: "group") {
            toggleExpansion()
        }
    }
    private func toggleExpansion() {
        expanded.toggle()
    }
    private func dismissGroup() {
        if let summary, summary.dismissible { commands.dismiss(summary) }
        else { for child in children where child.dismissible { commands.dismiss(child) } }
    }
    private func revealReply(_ target: NotificationCommandController.ReplyTarget?) {
        if let target, target.key == summary?.key || children.contains(where: { $0.key == target.key }) {
            expanded = true
        }
    }
}

/// Summary capabilities belong to the group, rather than an extra notification row.
struct NotificationGroupActions: View {
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

import SwiftUI
import PhoneCheckCore

private final class RowPresentation: ObservableObject {
    @Published var expanded: Bool
    init(expanded: Bool = false) { self.expanded = expanded }
}

struct RichNoticeRow: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    let summary: Notice?
    @StateObject private var presentation: RowPresentation
    private let expansion: Binding<Bool>?
    private let openPreview: (() -> Void)?
    private let swipeToDismiss: Bool
    private var expanded: Bool {
        get { expansion?.wrappedValue ?? presentation.expanded }
        nonmutating set {
            if let expansion { expansion.wrappedValue = newValue }
            else { presentation.expanded = newValue }
        }
    }

    init(notice: Notice, commands: NotificationCommandController, initiallyExpanded: Bool = false, summary: Notice? = nil, expansion: Binding<Bool>? = nil, openPreview: (() -> Void)? = nil, swipeToDismiss: Bool = true) {
        self.openPreview = openPreview
        self.swipeToDismiss = swipeToDismiss
        self.expansion = expansion
        self.notice = notice
        self.commands = commands
        self.summary = summary
        _presentation = StateObject(wrappedValue: RowPresentation(expanded: initiallyExpanded))
    }
    private var pending: Bool { commands.busyKeys.contains(notice.key) }
    private var actions: [NoticeAction] { notice.actions ?? [] }
    private var immediateControls: Bool { notice.kind == "media" || notice.kind == "call" }
    private var replying: Bool { commands.replyTarget?.key == notice.key }
    private var verticalPadding: CGFloat {
        (expanded ? 12 : 10) - (notice.dismissible ? 0 : 2)
    }
    private var showsFooter: Bool {
        expanded && !immediateControls && !replying && (!actions.isEmpty || notice.openable == true)
    }
    var body: some View {
        if notice.isMedia { MediaPlaybackView(notice: notice, commands: commands).padding(12) }
        else { notificationBody }
    }
    private var notificationBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if expanded {
                header
                VStack(alignment: .leading, spacing: 3) {
                    if !notice.title.isEmpty {
                        Text(notice.title).font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    content.textSelection(.enabled)
                }.modifier(PreviewContentOpen(action: openPreview))
            } else {
                NotificationPreview(notice: notice, open: openPreview) {
                    expansionButton
                }
            }
            if expanded, let image = NoticeImage.image(notice) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Notification image")
            }
            if let progress = notice.progress {
                if progress.indeterminate {
                    ProgressView().progressViewStyle(.linear).accessibilityLabel("In progress")
                } else {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(min(max(0, progress.value), max(1, progress.max))), total: Double(max(1, progress.max)))
                            .accessibilityLabel("Progress")
                        Text("\(Int(Double(min(max(0, progress.value), max(1, progress.max))) / Double(max(1, progress.max)) * 100))%")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            if !actions.isEmpty && immediateControls {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: notice.kind == "media" ? 12 : 8) { actionButtons }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 6) { actionButtons }
                }.padding(.top, 2)
            }
            NotificationReplyComposer(notice: notice, commands: commands)
            if let summary {
                NotificationReplyComposer(notice: summary, commands: commands)
                if let feedback = commands.feedback[summary.key] {
                    Text(feedback).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let feedback = commands.feedback[notice.key] {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if expanded && !immediateControls && !replying {
                if !actions.isEmpty {
                    NotificationActionFooter(actions: actions, pending: pending, perform: performAction)
                } else if notice.openable == true {
                    Button("Open on phone") { commands.open(notice) }
                        .buttonStyle(NotificationFooterActionStyle()).disabled(pending)
                }
            }
        }
        .padding(.horizontal, expanded ? 12 : 10)
        .padding(.top, verticalPadding)
        .padding(.bottom, showsFooter ? 4 : verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotificationCard(canDismiss: notice.dismissible && !pending, dismiss: { commands.dismiss(notice) }, swipeToDismiss: swipeToDismiss))
        .geometryGroup()
        .notificationMotion(value: expanded)
        .notificationMotion(value: notice)
        .notificationMotion(value: commands.replyTarget)
        .notificationMotion(value: commands.feedback)
        .accessibilityElement(children: .contain)
        .contextMenu {
            if notice.openable == true {
                Button("Open on phone") { commands.open(notice) }.disabled(pending)
            }
            if let summary {
                Divider()
                NotificationGroupActions(notice: summary, commands: commands)
            }
        }
        .onChange(of: commands.replyTarget) { _, target in
            if target?.key == notice.key { expanded = true }
        }
        .onAppear { if replying { expanded = true } }
    }
    private var header: some View {
        HStack(spacing: 7) {
            NoticeAppIcon(notice: notice, size: 18)
            Text(notice.app).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            NotificationTime(postedAt: notice.postedAt)
            expansionButton
        }
    }
    @ViewBuilder private var content: some View {
        if let messages = notice.messages, !messages.isEmpty {
            if expanded {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(message.sender).font(.caption.weight(.semibold))
                            Spacer()
                            Text(Date(timeIntervalSince1970: Double(message.time) / 1000), style: .time)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        NoticePreviewText(text: message.text.isEmpty && message.attachment ? "Attachment" : message.text,
                                          expanded: true, limit: 2)
                    }.padding(.top, 3)
                }
            } else if let message = messages.last {
                NoticePreviewText(text: "\(message.sender): \(message.text.isEmpty && message.attachment ? "Attachment" : message.text)",
                                  expanded: false, limit: 2)
            }
        } else if let lines = notice.lines, !lines.isEmpty {
            if expanded {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    NoticePreviewText(text: line, expanded: true, limit: 2)
                }
            } else {
                NoticePreviewText(text: lines[0], expanded: false, limit: 2)
            }
        } else if !notice.body.isEmpty {
            NoticePreviewText(text: notice.body, expanded: expanded, limit: 2)
        }
    }
    private var expansionButton: some View {
        NotificationChevron(expanded: expanded, subject: "notification", action: {
            expanded.toggle()
        }, busy: pending)
    }
    private var actionButtons: some View {
        ForEach(actions) { action in
            Button(role: action.destructive ? .destructive : nil) {
                performAction(action)
            } label: {
                HStack(spacing: 6) {
                    if let symbol = actionSymbol(action) {
                        Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    if action.requiresUnlock { Image(systemName: "lock").accessibilityHidden(true) }
                    if notice.kind != "media" || actionSymbol(action) == nil || action.input {
                        Text(action.title.isEmpty ? "Action" : action.title).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(minWidth: notice.kind == "media" ? 30 : 24, minHeight: notice.kind == "media" ? 30 : 24)
            }
            .modifier(NotificationActionStyle(color: actionColor(action), media: notice.kind == "media" && actionSymbol(action) != nil && !action.input, call: notice.kind == "call"))
            .accessibilityLabel(action.title.isEmpty ? "Action" : action.title)
            .disabled(pending || !action.enabled)
            .help(!action.enabled ? "Complete this action on your phone" : action.requiresUnlock ? "Requires an unlocked phone" : action.title)
        }
    }
    private func performAction(_ action: NoticeAction) {
        if action.input { commands.beginReply(notice, action: action) }
        else { commands.perform(notice, action: action) }
    }
    // Presentation hints only. Always execute the original opaque capability.
    // Unrecognized/localized labels retain text rather than guessing their meaning.
    private func actionSymbol(_ action: NoticeAction) -> String? {
        if action.input { return "arrowshape.turn.up.left" }
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if notice.kind == "call" {
            switch title {
            case "answer", "accept": return "phone.fill"
            case "decline", "reject", "hang up", "end", "end call": return "phone.down.fill"
            default: return nil
            }
        }
        return nil
    }
    private func actionColor(_ action: NoticeAction) -> Color? {
        if action.destructive { return Color.red }
        guard notice.kind == "call" else { return nil }
        switch actionSymbol(action) {
        case "phone.fill": return Color.green
        case "phone.down.fill": return Color.red
        default: return nil
        }
    }
}

private struct NotificationActionStyle: ViewModifier {
    let color: Color?
    var media = false
    var call = false
    @ViewBuilder func body(content: Content) -> some View {
        if media {
            content.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                .tint(.primary).foregroundStyle(.primary)
        } else if call, let color {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .tint(color).controlSize(.regular)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .tint(.primary).foregroundStyle(.primary)
        }
    }
}

private struct NoticePreviewText: View {
    let text: String
    let expanded: Bool
    let limit: Int
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.primary)
            .lineLimit(expanded ? nil : limit)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The content click target excludes expansion, footer actions, replies, and dismissal.
private struct PreviewContentOpen: ViewModifier {
    var action: (() -> Void)?
    @ViewBuilder func body(content: Content) -> some View {
        if let action { content.contentShape(Rectangle()).onTapGesture(perform: action) }
        else { content }
    }
}

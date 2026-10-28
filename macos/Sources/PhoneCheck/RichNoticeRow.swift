import SwiftUI
import PhoneCheckCore

private final class RowPresentation: ObservableObject {
    @Published var expanded: Bool
    init(expanded: Bool = false) { self.expanded = expanded }
    @Published var textTruncated = false
}

struct RichNoticeRow: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { colorScheme == .dark ? Color(red: 0.78, green: 0.68, blue: 1) : Palette.controlAccent }
    @StateObject private var presentation: RowPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(notice: Notice, commands: NotificationCommandController, initiallyExpanded: Bool = false) {
        self.notice = notice
        self.commands = commands
        _presentation = StateObject(wrappedValue: RowPresentation(expanded: initiallyExpanded))
    }
    @FocusState private var replyFocused: Bool
    private var pending: Bool { commands.pendingKeys.contains(notice.key) }
    private var actions: [NoticeAction] { notice.actions ?? [] }
    private var immediateControls: Bool { notice.kind == "media" || notice.kind == "call" }
    private var replying: Bool { commands.replyTarget?.key == notice.key }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if !notice.title.isEmpty {
                        Text(notice.title).font(.body.weight(.semibold))
                            .lineLimit(presentation.expanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    content.textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !presentation.expanded, let image = NoticeImage.image(notice) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: notice.kind == "media" ? 56 : 44, height: notice.kind == "media" ? 56 : 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(notice.kind == "media" ? "Album artwork" : "Notification image")
                }
            }
            if presentation.expanded, let image = NoticeImage.image(notice) {
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
            if !actions.isEmpty && (presentation.expanded || immediateControls) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: notice.kind == "media" ? 12 : 8) { actionButtons }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 6) { actionButtons }
                }.padding(.top, 2)
            }
            replyComposer
            if presentation.expanded && notice.openable == true {
                Button { commands.open(notice) } label: {
                    Label("Open on phone", systemImage: "iphone.and.arrow.forward")
                }.buttonStyle(.borderless).font(.caption).disabled(pending)
            }
            if let feedback = commands.feedback[notice.key] {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotificationCard(canDismiss: notice.dismissible && !pending) { commands.dismiss(notice) })
        .accessibilityElement(children: .contain)
        .onPreferenceChange(NoticeTextTruncated.self) { presentation.textTruncated = $0 }
        .onChange(of: commands.replyTarget) { _, target in
            if target?.key == notice.key { presentation.expanded = true }
        }
        .onAppear { if replying { presentation.expanded = true } }
    }
    private var header: some View {
        HStack(spacing: 7) {
            Group {
                if let icon = NoticeImage.icon(notice) {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: notice.kind == "call" ? "phone.fill" : notice.kind == "media" ? "music.note" : "app.fill")
                        .foregroundStyle(accent)
                }
            }.frame(width: 18, height: 18).accessibilityHidden(true)
            Text(notice.app).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            if pending {
                ProgressView().controlSize(.mini).accessibilityLabel("Waiting for phone")
            } else if notice.ongoing == true {
                Text("Ongoing").font(.caption2).foregroundStyle(.secondary)
            } else if notice.postedAt > 0 {
                Text(Date(timeIntervalSince1970: Double(notice.postedAt) / 1000), style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if needsExpansion { expansionButton }
        }.padding(.trailing, notice.dismissible ? 26 : 0)
    }
    @ViewBuilder private var content: some View {
        if let messages = notice.messages, !messages.isEmpty {
            if presentation.expanded {
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
            if presentation.expanded {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    NoticePreviewText(text: line, expanded: true, limit: 2)
                }
            } else {
                NoticePreviewText(text: lines[0], expanded: false, limit: 2)
            }
        } else if !notice.body.isEmpty {
            NoticePreviewText(text: notice.body, expanded: presentation.expanded, limit: 2)
        }
    }
    private var needsExpansion: Bool {
        presentation.expanded || presentation.textTruncated || !actions.isEmpty || notice.openable == true ||
        !notice.title.isEmpty || (notice.messages?.count ?? 0) > 1 || (notice.lines?.count ?? 0) > 1 || notice.image != nil
    }
    private var expansionButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { presentation.expanded.toggle() }
        } label: {
            Image(systemName: presentation.expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24).contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .accessibilityLabel(presentation.expanded ? "Collapse notification" : "Expand notification")
        .accessibilityValue(presentation.expanded ? "Expanded" : "Collapsed")
        .help(presentation.expanded ? "Collapse" : "Details and actions")
    }
    private var actionButtons: some View {
        ForEach(actions) { action in
            Button(role: action.destructive ? .destructive : nil) {
                if action.input { commands.beginReply(notice, action: action) }
                else { commands.perform(notice, action: action) }
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
            .modifier(NotificationActionStyle(color: actionColor(action), media: notice.kind == "media" && actionSymbol(action) != nil && !action.input))
            .accessibilityLabel(action.title.isEmpty ? "Action" : action.title)
            .disabled(pending || !action.enabled)
            .help(!action.enabled ? "Complete this action on your phone" : action.requiresUnlock ? "Requires an unlocked phone" : action.title)
        }
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
        if notice.kind == "media" {
            switch title {
            case "play", "resume": return "play.fill"
            case "pause": return "pause.fill"
            case "next", "next track", "skip next": return "forward.end.fill"
            case "previous", "previous track", "skip previous": return "backward.end.fill"
            case "stop": return "stop.fill"
            default: return nil
            }
        }
        return nil
    }
    private func actionColor(_ action: NoticeAction) -> Color? {
        if action.destructive { return Color(red: 0.76, green: 0.12, blue: 0.16) }
        guard notice.kind == "call" else { return nil }
        switch actionSymbol(action) {
        case "phone.fill": return Color(red: 0.12, green: 0.47, blue: 0.25)
        case "phone.down.fill": return Color(red: 0.76, green: 0.12, blue: 0.16)
        default: return nil
        }
    }
    @ViewBuilder private var replyComposer: some View {
        if let target = commands.replyTarget, target.key == notice.key,
           let action = actions.first(where: { $0.id == target.action }) {
            VStack(alignment: .leading, spacing: 7) {
                if action.freeform {
                    TextField("Reply", text: $commands.replyDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                        .focused($replyFocused)
                        .onAppear { replyFocused = true }
                        .accessibilityLabel("Reply to \(notice.app)")
                        .onChange(of: commands.replyDraft) { _, value in
                            if value.utf16.count > 4000 {
                                var bounded = "", count = 0
                                for character in value {
                                    let size = character.utf16.count
                                    if count + size > 4000 { break }
                                    bounded.append(character); count += size
                                }
                                commands.replyDraft = bounded
                            }
                        }
                }
                HStack {
                    if !action.choices.isEmpty {
                        Menu("Suggestions") {
                            ForEach(action.choices, id: \.self) { choice in
                                Button(choice) { commands.perform(notice, action: action, text: choice) }
                            }
                        }.disabled(pending)
                    }
                    if action.freeform {
                        Button("Send") { commands.perform(notice, action: action, text: commands.replyDraft) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(pending || commands.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button("Cancel") { commands.replyTarget = nil; commands.replyDraft = "" }.disabled(pending)
                }.controlSize(.small)
            }.padding(.top, 4)
        }
    }
}

private struct NotificationActionStyle: ViewModifier {
    let color: Color?
    var media = false
    @ViewBuilder func body(content: Content) -> some View {
        if media {
            content.buttonStyle(.borderless)
                .padding(3).background(.quaternary, in: Circle())
        } else if let color {
            content.buttonStyle(.borderedProminent).tint(color).controlSize(.small)
        } else {
            content.buttonStyle(.bordered).controlSize(.small)
        }
    }
}

private struct NoticeTextTruncated: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
private struct PreviewHeights: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private final class PreviewMeasurement: ObservableObject {
    @Published var truncated = false
}
/// Measure real line wrapping, including newlines, localized text and font scaling.
private struct NoticePreviewText: View {
    let text: String
    let expanded: Bool
    let limit: Int
    @StateObject private var measurement = PreviewMeasurement()
    var body: some View {
        Text(text).lineLimit(expanded ? nil : limit)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                ZStack(alignment: .topLeading) {
                    Text(text).lineLimit(limit).fixedSize(horizontal: false, vertical: true)
                        .background { height("limited") }
                    Text(text).fixedSize(horizontal: false, vertical: true)
                        .background { height("full") }
                }.hidden().accessibilityHidden(true)
            }
            .font(.subheadline).foregroundStyle(.secondary)
            .onPreferenceChange(PreviewHeights.self) { sizes in
                measurement.truncated = (sizes["full"] ?? 0) > (sizes["limited"] ?? 0) + 1
            }
            .preference(key: NoticeTextTruncated.self, value: measurement.truncated)
    }
    private func height(_ key: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: PreviewHeights.self, value: [key: proxy.size.height])
        }
    }
}

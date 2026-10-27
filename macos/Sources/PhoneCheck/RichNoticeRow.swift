import SwiftUI
import PhoneCheckCore

private final class RowPresentation: ObservableObject {
    @Published var expanded = false
}

struct RichNoticeRow: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { colorScheme == .dark ? Color(red: 0.78, green: 0.68, blue: 1) : Palette.controlAccent }
    @StateObject private var presentation = RowPresentation()
    private var pending: Bool { commands.pendingKeys.contains(notice.key) }
    private var actions: [NoticeAction] { notice.actions ?? [] }
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Group {
                if let icon = NoticeImage.icon(notice) {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Text(String(notice.app.prefix(1)).uppercased())
                        .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }.frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(notice.app).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if notice.groupSummary == true { Text("Group").font(.caption2).foregroundStyle(.secondary) }
                    if notice.ongoing == true { Image(systemName: "pin").font(.caption2).foregroundStyle(.secondary).help("Ongoing notification") }
                }
                if !notice.title.isEmpty { Text(notice.title).font(.body.weight(.semibold)) }
                content
                if let image = NoticeImage.image(notice) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Notification image")
                }
                if let progress = notice.progress {
                    if progress.indeterminate {
                        ProgressView().progressViewStyle(.linear).accessibilityLabel("In progress")
                    } else {
                        ProgressView(value: Double(progress.value), total: Double(max(1, progress.max)))
                            .accessibilityLabel("Progress")
                        Text("\(Int(Double(progress.value) / Double(max(1, progress.max)) * 100))%")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if !actions.isEmpty {
                    Group {
                        if actions.count <= 3 && actions.reduce(0, { $0 + $1.title.count }) <= 28 {
                            HStack(spacing: 6) { actionButtons }
                        } else {
                            VStack(alignment: .leading, spacing: 6) { actionButtons }
                        }
                    }.padding(.top, 2)
                }
                replyComposer
                HStack(spacing: 12) {
                    if notice.openable == true {
                        Button("Open on phone") { commands.open(notice) }
                            .disabled(pending).foregroundStyle(accent)
                    }
                    if notice.dismissible {
                        Button(pending ? "Waiting…" : "Dismiss on phone") { commands.dismiss(notice) }
                            .disabled(pending).foregroundStyle(accent)
                    } else {
                        Text("Cannot dismiss").foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).font(.caption.weight(.medium)).padding(.top, 4)
                if let feedback = commands.feedback[notice.key] {
                    Text(feedback).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private var content: some View {
        if let messages = notice.messages, !messages.isEmpty {
            let visible = presentation.expanded ? messages : Array(messages.suffix(4))
            ForEach(Array(visible.enumerated()), id: \.offset) { _, message in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(message.sender).font(.caption.weight(.semibold))
                        Spacer()
                        Text(Date(timeIntervalSince1970: Double(message.time) / 1000), style: .time)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(message.text.isEmpty && message.attachment ? "Attachment" : message.text)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(presentation.expanded ? nil : 3)
                }
            }
            if messages.count > 4 { expansionButton }
        } else if let lines = notice.lines, !lines.isEmpty {
            ForEach(Array((presentation.expanded ? lines : Array(lines.prefix(5))).enumerated()), id: \.offset) { _, line in
                Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(presentation.expanded ? nil : 2)
            }
            if lines.count > 5 { expansionButton }
        } else if !notice.body.isEmpty {
            Text(notice.body).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(presentation.expanded ? nil : 5).textSelection(.enabled)
            if notice.body.count > 240 { expansionButton }
        }
    }
    private var expansionButton: some View {
        Button(presentation.expanded ? "Show less" : "Show more") { presentation.expanded.toggle() }
            .buttonStyle(.plain).font(.caption).foregroundStyle(accent)
    }
    private var actionButtons: some View {
        ForEach(actions) { action in
            Button(role: action.destructive ? .destructive : nil) {
                if action.input { commands.beginReply(notice, action: action) }
                else { commands.perform(notice, action: action) }
            } label: {
                HStack(spacing: 3) {
                    if action.requiresUnlock { Image(systemName: "lock").accessibilityHidden(true) }
                    Text(action.title.isEmpty ? "Action" : action.title).lineLimit(2)
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(pending || !action.enabled)
            .help(!action.enabled ? "Complete this action on your phone" : action.requiresUnlock ? "Requires an unlocked phone" : action.title)
        }
    }
    @ViewBuilder private var replyComposer: some View {
        if let target = commands.replyTarget, target.key == notice.key,
           let action = actions.first(where: { $0.id == target.action }) {
            VStack(alignment: .leading, spacing: 7) {
                if action.freeform {
                    TextField("Reply", text: $commands.replyDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
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
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(pending || commands.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button("Cancel") { commands.replyTarget = nil; commands.replyDraft = "" }.disabled(pending)
                }.controlSize(.small)
            }.padding(.top, 4)
        }
    }
}

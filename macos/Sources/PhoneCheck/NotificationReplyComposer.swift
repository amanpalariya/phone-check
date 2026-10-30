import SwiftUI
import PhoneCheckCore

struct NotificationReplyComposer: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    @FocusState private var replyFocused: Bool
    private var pending: Bool { commands.busyKeys.contains(notice.key) }
    private var actions: [NoticeAction] { notice.actions ?? [] }
    @ViewBuilder var body: some View {
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
                if !action.choices.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { choices(action) }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 6) { choices(action) }
                    }
                }
                HStack(spacing: 0) {
                    if action.freeform {
                        Button("Send") { commands.perform(notice, action: action, text: commands.replyDraft) }
                            .buttonStyle(NotificationFooterActionStyle())
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(pending || commands.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if action.freeform {
                        Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 14).accessibilityHidden(true)
                    }
                    Button("Cancel") { commands.replyTarget = nil; commands.replyDraft = "" }
                        .buttonStyle(NotificationFooterActionStyle()).disabled(pending)
                }.controlSize(.small)
            }.padding(.top, 4)
        }
    }
    private func choices(_ action: NoticeAction) -> some View {
        ForEach(action.choices, id: \.self) { choice in
            Button { commands.perform(notice, action: action, text: choice) } label: {
                Text(choice).fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(NotificationSuggestionStyle()).disabled(pending)
        }
    }
}

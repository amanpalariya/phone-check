import SwiftUI
import PhoneCheckCore

private final class MediaSelection: ObservableObject {
    @Published var key: String?
}

/// Playback belongs to the panel header, independently of notification search and grouping.
struct MediaShelf: View {
    let notices: [Notice]
    @ObservedObject var commands: NotificationCommandController
    @StateObject private var selection = MediaSelection()
    private var selected: Notice? { notices.first { $0.key == selection.key } ?? notices.first }
    var body: some View {
        if let notice = selected {
            VStack(spacing: 10) {
                if notices.count > 1 {
                    HStack {
                        Text(notice.app).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous media session")
                        Text("\((notices.firstIndex { $0.key == notice.key } ?? 0) + 1) / \(notices.count)")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Next media session")
                    }.buttonStyle(.borderless).tint(.primary)
                }
                MediaPlaybackView(notice: notice, commands: commands)
            }
            .padding(.vertical, 12)
            .onChange(of: notices.map(\.key)) { _, keys in
                if let key = selection.key, !keys.contains(key) { selection.key = nil }
            }
        }
    }
    private func step(_ offset: Int) {
        guard let selected, let index = notices.firstIndex(where: { $0.key == selected.key }), !notices.isEmpty else { return }
        selection.key = notices[(index + offset + notices.count) % notices.count].key
    }
}

private final class MediaSeekPresentation: ObservableObject {
    @Published var draft: Double?
    @Published var editing = false
    private var timer: Timer?
    func cancel() { timer?.invalidate(); timer = nil }
    func schedule(_ action: @escaping () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in action() }
    }
    deinit { timer?.invalidate() }
}

struct MediaPlaybackView: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    @StateObject private var seeking = MediaSeekPresentation()
    private var pending: Bool { commands.pendingKeys.contains(notice.key) }
    private var seekAction: NoticeAction? { notice.actions?.first { $0.mediaControl == "seek" && $0.enabled } }
    private var actions: [NoticeAction] { (notice.actions ?? []).filter { $0.mediaControl != "seek" } }
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06))
                    if let artwork = NoticeImage.image(notice) {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                    }
                }.frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title.isEmpty ? notice.app : notice.title).font(.body.weight(.semibold)).lineLimit(2)
                    if !notice.body.isEmpty { Text(notice.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    HStack(spacing: 4) {
                        NoticeAppIcon(notice: notice, size: 12)
                        Text(notice.app).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if pending || notice.media?.buffering == true {
                    ProgressView().controlSize(.small).accessibilityLabel(pending ? "Waiting for phone" : "Buffering")
                }
            }
            if let media = notice.media, media.duration > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let position = seeking.draft ?? media.position(at: context.date)
                    VStack(spacing: 3) {
                        if let seekAction {
                            Slider(value: Binding(get: { min(Double(media.duration), max(0, position)) },
                                                  set: { value in
                                seeking.draft = value
                                if !seeking.editing { seeking.schedule { commitSeek(seekAction, position: value) } }
                            }), in: 0...Double(media.duration),
                                   onEditingChanged: { editing in
                                seeking.editing = editing
                                seeking.cancel()
                                if !editing, let target = seeking.draft { commitSeek(seekAction, position: target) }
                            })
                            .controlSize(.small).tint(.primary).disabled(pending)
                            .accessibilityLabel("Playback position")
                            .accessibilityValue("\(time(position)) of \(time(Double(media.duration)))")
                        } else {
                            ProgressView(value: position, total: Double(media.duration)).tint(.primary)
                                .accessibilityLabel("Playback position")
                                .accessibilityValue("\(time(position)) of \(time(Double(media.duration)))")
                        }
                        HStack {
                            Text(time(position)); Spacer(); Text(time(Double(media.duration)))
                        }.font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(Array(actions.prefix(5))) { action in
                        Button { perform(action) } label: {
                            actionLabel(action)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.circle)
                        .tint(.primary).foregroundStyle(.primary)
                        .disabled(pending || !action.enabled)
                        .accessibilityLabel(action.title.isEmpty ? "Media action" : action.title)
                        .help(action.requiresUnlock ? "Requires an unlocked phone" : action.title)
                    }
                    if actions.count > 5 {
                        Menu {
                            ForEach(Array(actions.dropFirst(5))) { action in
                                Button(action.title) { perform(action) }.disabled(pending || !action.enabled)
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 24, height: 34) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("More media controls")
                    }
                    Spacer(minLength: 0)
                }
            }
            NotificationReplyComposer(notice: notice, commands: commands)
            if let feedback = commands.feedback[notice.key] {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: seekAction?.id) { _, _ in seeking.cancel(); seeking.draft = nil; seeking.editing = false }
        .contextMenu {
            if notice.openable == true { Button("Open on phone") { commands.open(notice) }.disabled(pending) }
            if notice.dismissible { Button("Dismiss on phone") { commands.dismiss(notice) }.disabled(pending) }
        }
    }
    @ViewBuilder private func actionLabel(_ action: NoticeAction) -> some View {
        if let symbol = symbol(action.mediaControl) {
            Image(systemName: symbol).font(.system(size: action.mediaControl == "play" || action.mediaControl == "pause" ? 19 : 14, weight: .semibold))
        } else if let icon = NoticeImage.actionIcon(action) {
            Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit().frame(width: 19, height: 19)
        } else {
            Text(action.title.isEmpty ? "Action" : action.title).font(.caption2).lineLimit(2).minimumScaleFactor(0.8)
        }
    }
    private func symbol(_ control: String?) -> String? {
        switch control {
        case "play": "play.fill"
        case "pause": "pause.fill"
        case "previous": "backward.end.fill"
        case "next": "forward.end.fill"
        case "rewind": "backward.fill"
        case "fastForward": "forward.fill"
        case "stop": "stop.fill"
        default: nil
        }
    }
    private func commitSeek(_ action: NoticeAction, position: Double) {
        seeking.cancel()
        commands.seek(notice, action: action, position: Int64(position.rounded()))
        seeking.draft = nil
    }
    private func perform(_ action: NoticeAction) {
        if action.input { commands.beginReply(notice, action: action) }
        else { commands.perform(notice, action: action) }
    }
    private func time(_ milliseconds: Double) -> String {
        let seconds = Int(max(0, milliseconds) / 1000)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

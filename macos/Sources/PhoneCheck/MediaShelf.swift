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
                MediaPlaybackView(notice: notice, commands: commands).id(notice.key)
            }
            .padding(.vertical, 12)
            .onAppear {
                if !notices.contains(where: { $0.key == selection.key }) { selection.key = notice.key }
            }
            .onChange(of: notices.map(\.key)) { _, keys in
                if let key = selection.key, !keys.contains(key) { selection.key = keys.first }
            }
        }
    }
    private func step(_ offset: Int) {
        guard let selected, let index = notices.firstIndex(where: { $0.key == selected.key }), !notices.isEmpty else { return }
        selection.key = notices[(index + offset + notices.count) % notices.count].key
    }
}

final class MediaSeekPresentation: ObservableObject {
    private struct Confirmation {
        let position: Double
        let sentAt: Date
        let previousUpdate: Int64
    }
    private var confirmation: Confirmation?
    private var confirmationTimer: Timer?
    @Published private(set) var failure: String?
    @Published var draft: Double?
    @Published var editing = false
    @Published var buffering = false
    private var timer: Timer?
    func cancel() { timer?.invalidate(); timer = nil }
    func schedule(_ action: @escaping () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in action() }
    }
    func updateDraft(_ position: Double) {
        clearConfirmation()
        failure = nil
        draft = position
    }
    func beginSeek(_ position: Double, media: NoticeMedia, at date: Date = .now) {
        clearConfirmation()
        failure = nil
        draft = position
        confirmation = Confirmation(position: position, sentAt: date, previousUpdate: media.updatedAt)
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.reset()
            self?.failure = "Seek not confirmed"
        }
    }
    func position(media: NoticeMedia, at date: Date) -> Double {
        guard let draft else { return media.position(at: date) }
        guard !editing, let confirmation else { return draft }
        let elapsed = max(0, date.timeIntervalSince(confirmation.sentAt) * 1000)
        let position = confirmation.position + (media.playing ? elapsed * media.speed : 0)
        return min(Double(media.duration), max(0, position))
    }
    func reconcile(_ media: NoticeMedia, at date: Date = .now) {
        guard !editing, let confirmation, media.updatedAt > confirmation.previousUpdate else { return }
        // Ignore old/in-flight phone positions until playback actually reaches the seek target.
        if abs(media.position(at: date) - position(media: media, at: date)) <= 1500 {
            clearConfirmation()
            draft = nil
        }
    }
    func reset() {
        cancel(); clearConfirmation()
        draft = nil; editing = false; failure = nil
    }
    private func clearConfirmation() {
        confirmationTimer?.invalidate(); confirmationTimer = nil; confirmation = nil
    }
    deinit { timer?.invalidate(); confirmationTimer?.invalidate() }
}

struct MediaPlaybackView: View {
    let notice: Notice
    @ObservedObject var commands: NotificationCommandController
    @StateObject private var seeking = MediaSeekPresentation()
    private var pending: Bool { commands.busyKeys.contains(notice.key) }
    private var seekAction: NoticeAction? { notice.actions?.first { $0.mediaControl == "seek" && $0.enabled } }
    private var actions: [NoticeAction] { (notice.actions ?? []).filter { $0.mediaControl != "seek" } }
    private struct Control: Identifiable {
        let action: NoticeAction
        // Keep the primary button mounted when its capability changes Play ↔ Pause.
        var id: String {
            action.mediaControl == "play" || action.mediaControl == "pause" ? "playback" : action.id
        }
    }
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
                NotificationBusyIndicator(visible: pending || seeking.buffering,
                                          label: pending ? "Waiting for phone" : "Buffering")
            }
            if let media = notice.media, media.duration > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let position = seeking.position(media: media, at: context.date)
                    VStack(spacing: 3) {
                        if let seekAction {
                            Slider(value: Binding(get: { min(Double(media.duration), max(0, position)) },
                                                  set: { value in
                                seeking.updateDraft(value)
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
                    ForEach(actions.prefix(5).map { Control(action: $0) }) { control in
                        let action = control.action
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
            if let feedback = commands.feedback[notice.key] ?? seeking.failure {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        // Playback updates are direct state changes, not notification insertion transitions.
        .transaction { $0.animation = nil }
        .task(id: notice.media?.buffering == true) {
            seeking.buffering = false
            guard notice.media?.buffering == true else { return }
            do {
                try await Task.sleep(for: .seconds(NotificationCommandController.feedbackDelay))
                try Task.checkCancellation()
                seeking.buffering = true
            } catch { }
        }
        .onChange(of: seekAction?.id) { _, _ in seeking.reset() }
        .onChange(of: notice.media) { _, media in if let media { seeking.reconcile(media) } }
        .onChange(of: commands.feedback[notice.key]) { _, feedback in if feedback != nil { seeking.reset() } }
        .onDisappear { seeking.reset() }
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
        guard let media = notice.media else { seeking.reset(); return }
        let target = min(Double(media.duration), max(0, position))
        if commands.seek(notice, action: action, position: Int64(target.rounded())) {
            seeking.beginSeek(target, media: media)
        } else { seeking.reset() }
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

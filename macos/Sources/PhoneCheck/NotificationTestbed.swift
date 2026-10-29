import SwiftUI
import PhoneCheckCore

/// A simulated phone shared by the testbed window and optional floating-pane preview.
final class NotificationTestbed: ObservableObject {
    @Published private(set) var notices: [Notice] = []
    @Published private(set) var receipt = ""
    @Published var result = "sent"
    @Published var showsInPane = false
    private var generation = 0
    lazy var commands = NotificationCommandController(
        current: { [weak self] key in self?.notices.first { $0.key == key } },
        connected: { true },
        send: { [weak self] message in self?.execute(message) }
    )

    func show(_ kind: NotificationFixtures.Kind) {
        let samples = NotificationFixtures.make(kind)
        generation += 1
        for var sample in samples {
            sample.revision = String(generation)
            commands.notificationChanged(sample)
            notices.removeAll { $0.key == sample.key }
            notices.append(sample)
        }
    }
    func showAll() {
        clear()
        NotificationFixtures.Kind.allCases.forEach(show)
    }
    func clear() {
        generation += 1; commands.reset(); notices = []; receipt = ""
    }
    func updateLatest() {
        guard var notice = notices.last else { return }
        generation += 1; notice.revision = String(generation)
        notice.title = "Updated notification"
        if notice.progress != nil { notice.progress?.value = 85 }
        commands.notificationChanged(notice)
        notices[notices.count - 1] = notice
        receipt = "Sample updated"
    }
    func removeLatest() {
        guard let notice = notices.last else { return }
        remove(notice)
        receipt = "Sample removed"
    }
    private func remove(_ notice: Notice) {
        let removed = notices.filter { $0.key == notice.key || (notice.groupSummary == true && $0.groupKey == notice.groupKey) }
        notices.removeAll { item in removed.contains { $0.key == item.key } }
        removed.forEach { commands.notificationRemoved($0.key) }
    }
    private func execute(_ message: Message) {
        let outcome = result
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let id = message.command,
                  let notice = notices.first(where: { $0.key == message.key }),
                  notice.revision == message.revision else { return }
            if outcome == "timeout" { receipt = "Simulating no response"; return }
            let status = outcome == "sent" && message.type == "dismiss" ? "removed" : outcome
            let removal = commands.receiveResult(id: id, status: status)
            if let removal, removal.revision == notice.revision { remove(notice) }
            let action = notice.actions?.first { $0.id == message.action }?.title
            let label = message.type == "dismiss" ? "Dismiss" : message.type == "open" ? "Open" : action ?? "Action"
            receipt = "\(label) · \(status)" + (message.text.map { " · \($0)" } ?? "")
        }
    }
}

struct NotificationTestbedView: View {
    @StateObject private var model = NotificationTestbed()
    init(model: NotificationTestbed = NotificationTestbed()) {
        _model = StateObject(wrappedValue: model)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notification testbed").font(.headline)
                Text("Local samples · no phone needed").font(.caption).foregroundStyle(.secondary)
                Toggle("Show in notification pane", isOn: $model.showsInPane)
                    .toggleStyle(.switch).controlSize(.small)
                Text("Click Phone Check in the menu bar.").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(NotificationFixtures.Kind.allCases) { kind in
                            Button { model.show(kind) } label: {
                                HStack { Text(kind.rawValue); Spacer(); Image(systemName: "plus") }
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.borderless).tint(.primary).padding(.vertical, 4)
                                .accessibilityLabel("Show \(kind.rawValue)")
                        }
                    }.padding(.horizontal, 2)
                }
                Button("Show all", action: model.showAll).frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                HStack {
                    Button("Update last", action: model.updateLatest)
                    Button("Remove last", action: model.removeLatest)
                }.disabled(model.notices.isEmpty)
                Picker("Action result", selection: $model.result) {
                    Text("Success").tag("sent")
                    Text("Failed").tag("failed")
                    Text("Unlock required").tag("requires_unlock")
                    Text("Expired").tag("expired")
                    Text("No response").tag("timeout")
                }.font(.caption)
                Button("Clear", action: model.clear).disabled(model.notices.isEmpty)
            }.padding(16).frame(width: 240)
            Divider()
            VStack(spacing: 8) {
                HStack {
                    Text("Preview").font(.headline)
                    Spacer()
                    Text("\(NotificationSection.count(model.notices))").monospacedDigit().foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.top, 16)
                if model.notices.isEmpty {
                    ContentUnavailableView("Choose a sample", systemImage: "bell", description: Text("Use the controls on the left."))
                } else {
                    NotificationFeed(notices: model.notices, commands: model.commands)
                }
                Spacer(minLength: 0)
                if !model.receipt.isEmpty {
                    Text(model.receipt).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(3).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                Text("Actions and dismissals are simulated.").font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }.frame(width: 340)
        }.frame(height: 680).background(.regularMaterial)
        #if PHONECHECK_VISUAL_TEST
        .onAppear { if CommandLine.arguments.contains("--samples") { model.showAll() } }
        #endif
    }
}

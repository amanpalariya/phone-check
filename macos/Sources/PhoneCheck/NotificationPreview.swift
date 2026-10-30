import SwiftUI
import PhoneCheckCore

struct NoticeAppIcon: View {
    let notice: Notice
    let size: CGFloat
    var body: some View {
        Group {
            if let icon = NoticeImage.icon(notice) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Text(String(notice.app.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.24))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Keep the time beside the title without adding height to collapsed rows.
struct NotificationPreview<Trailing: View>: View {
    let notice: Notice
    var count: Int? = nil
    var open: (() -> Void)? = nil
    @ViewBuilder let trailing: () -> Trailing
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 34
    private var preview: String {
        if let message = notice.messages?.last {
            return "\(message.sender): \(message.text.isEmpty && message.attachment ? "Attachment" : message.text)"
        }
        return notice.lines?.first ?? notice.body
    }
    var body: some View {
        HStack(spacing: 10) {
            if let open {
                Button(action: open) { previewContent.contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityHint("Open notifications")
            } else { previewContent }
            trailing()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.app)
    }
    private var previewContent: some View {
        HStack(spacing: 10) {
            NoticeAppIcon(notice: notice, size: iconSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !notice.title.isEmpty {
                        Text(notice.title).font(.body.weight(.semibold)).lineLimit(1)
                    }
                    if let count { Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                    Spacer(minLength: 4)
                    NotificationTime(postedAt: notice.postedAt)
                }
                if !preview.isEmpty {
                    Text(preview).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let image = NoticeImage.image(notice) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Notification image")
            }
        }
    }

}

struct NotificationTime: View {
    let postedAt: Int64
    var body: some View {
        if postedAt > 0 {
            Text(Date(timeIntervalSince1970: Double(postedAt) / 1000), style: .time)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

struct NotificationChevron: View {
    let expanded: Bool
    let subject: String
    let action: () -> Void
    var busy = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
                .opacity(busy ? 0 : 1)
                .overlay { NotificationBusyIndicator(visible: busy) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(subject)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .help(expanded ? "Collapse" : "Expand")
    }
}

/// Fixed space and no transition: busy feedback never moves surrounding content.
struct NotificationBusyIndicator: View {
    let visible: Bool
    var label = "Waiting for phone"
    var body: some View {
        ProgressView().controlSize(.mini)
            .frame(width: 16, height: 16)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityLabel(label).accessibilityHidden(!visible)
            .transaction { $0.animation = nil }
    }
}

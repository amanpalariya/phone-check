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

/// Collapsed rows spend their height on the app icon and message, not metadata.
struct NotificationPreview<Trailing: View>: View {
    let notice: Notice
    var count: Int? = nil
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
            NoticeAppIcon(notice: notice, size: iconSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !notice.title.isEmpty {
                        Text(notice.title).font(.body.weight(.semibold)).lineLimit(1)
                    }
                    if let count { Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
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
            trailing()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.app)
    }
}

struct NotificationChevron: View {
    let expanded: Bool
    let subject: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(subject)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .help(expanded ? "Collapse" : "Expand")
    }
}

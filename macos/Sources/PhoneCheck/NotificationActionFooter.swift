import SwiftUI
import PhoneCheckCore

/// One UI's ordinary actions share a footer; suggestions have separate chips.
struct NotificationActionFooter: View {
    let actions: [NoticeAction]
    let pending: Bool
    let perform: (NoticeAction) -> Void
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: actions.count, by: 3)), id: \.self) { start in
                HStack(spacing: 0) {
                    ForEach(Array(actions[start..<min(start + 3, actions.count)].enumerated()), id: \.element.id) { index, action in
                        if index > 0 {
                            Rectangle().fill(.secondary.opacity(0.35))
                                .frame(width: 1, height: 14).accessibilityHidden(true)
                        }
                        Button(role: action.destructive ? .destructive : nil) { perform(action) } label: {
                            Text(action.title.isEmpty ? "Action" : action.title)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(NotificationFooterActionStyle(destructive: action.destructive))
                        .disabled(pending || !action.enabled)
                        .help(!action.enabled ? "Complete this action on your phone" : action.requiresUnlock ? "Requires an unlocked phone" : action.title)
                    }
                }
            }
        }.padding(.top, 4)
    }
}

struct NotificationFooterActionStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle()).opacity(enabled ? 1 : 0.4)
    }
}

struct NotificationSuggestionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline).foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 30)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08), in: Capsule())
            .contentShape(Capsule()).opacity(enabled ? 1 : 0.4)
    }
}

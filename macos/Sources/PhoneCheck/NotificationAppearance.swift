import AppKit
import Combine
import SwiftUI

/// A single saved preference shared by the native backdrop and its SwiftUI control.
final class NotificationAppearance: ObservableObject {
    static let shared = NotificationAppearance()
    @Published var transparency: Double {
        didSet { defaults.set(transparency, forKey: Self.key) }
    }
    private let defaults: UserDefaults
    private static let key = "notificationBackdropTransparency"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Self.key) as? Double ?? 0.35
        transparency = saved.isFinite ? min(1, max(0, saved)) : 0.35
    }
}

private final class AppearanceSettingsState: ObservableObject {
    @Published var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
}

struct NotificationAppearanceSettings: View {
    @ObservedObject private var appearance = NotificationAppearance.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = AppearanceSettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance").font(.headline)
            VStack(spacing: 8) {
                HStack {
                    Text("Backdrop transparency")
                    Spacer()
                    Text(appearance.transparency, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $appearance.transparency, in: 0...1)
                    .accessibilityLabel("Backdrop transparency")
                    .disabled(state.reduceTransparency)
                HStack {
                    Text("Frosted")
                    Spacer()
                    Text("Clear")
                }.font(.caption).foregroundStyle(.secondary)
            }
            if state.reduceTransparency {
                Text("Reduce Transparency is on.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 320)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            state.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    }
}

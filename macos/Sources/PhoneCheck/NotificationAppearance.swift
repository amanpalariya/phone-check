import AppKit
import Combine
import SwiftUI

/// Saved appearance preferences shared by the native backdrop and its SwiftUI control.
final class NotificationAppearance: ObservableObject {
    static let shared = NotificationAppearance()
    @Published var usesSystemBackdrop: Bool {
        didSet { defaults.set(usesSystemBackdrop, forKey: Self.systemKey) }
    }
    @Published var blurAmount: Double {
        didSet { defaults.set(blurAmount, forKey: Self.blurKey) }
    }
    @Published var transparency: Double {
        didSet { defaults.set(transparency, forKey: Self.key) }
    }
    private let defaults: UserDefaults
    private static let key = "notificationBackdropTransparency"
    private static let blurKey = "notificationBackdropBlur"
    private static let systemKey = "usesSystemNotificationBackdrop"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usesSystemBackdrop = defaults.object(forKey: Self.systemKey) as? Bool ?? true
        let savedBlur = defaults.object(forKey: Self.blurKey) as? Double ?? 2
        blurAmount = savedBlur.isFinite ? min(12, max(0, savedBlur)) : 2
        let saved = defaults.object(forKey: Self.key) as? Double ?? 0.35
        transparency = saved.isFinite ? min(1, max(0, saved)) : 0.35
    }
}

private final class AppearanceSettingsState: ObservableObject {
    let supportsBlurControl = CompositorBackdrop(frame: .zero).isAvailable
    @Published var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
}

struct NotificationAppearanceSettings: View {
    @ObservedObject private var appearance = NotificationAppearance.shared
    var close: () -> Void
    @StateObject private var state = AppearanceSettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance").font(.headline)
            Picker("Backdrop", selection: $appearance.usesSystemBackdrop) {
                Text("Automatic").tag(true)
                Text("Custom").tag(false)
            }.pickerStyle(.segmented)
            if state.supportsBlurControl {
                VStack(spacing: 8) {
                    HStack {
                        Text("Blur amount")
                        Spacer()
                        Text(appearance.blurAmount, format: .number.precision(.fractionLength(0)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $appearance.blurAmount, in: 0...12)
                        .accessibilityLabel("Blur amount")
                        .disabled(state.reduceTransparency)
                }
            }
            if !appearance.usesSystemBackdrop {
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
            }
            if state.reduceTransparency {
                Text("Reduce Transparency is on.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 320)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            state.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    }
}

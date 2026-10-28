import SwiftUI
import PhoneCheckCore

/// One interruptible curve for layout, content replacement and viewport resizing.
/// State drives animations; there are no delayed removals or completion callbacks
/// that could replay stale presentation after a newer notification update.
enum NotificationMotion {
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.28, extraBounce: 0)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(y: -6))
    }
}

private struct NotificationMotionModifier<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .transition(NotificationMotion.transition(reduceMotion: reduceMotion))
            .animation(NotificationMotion.animation(reduceMotion: reduceMotion), value: value)
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
            }
    }
}

extension View {
    func notificationMotion<Value: Equatable>(value: Value) -> some View {
        modifier(NotificationMotionModifier(value: value))
    }
}

/// Expansion belongs to Android identities, rather than to a temporary group
/// subtree. Filtering, regrouping and collapsing a stack must not reset a row.
final class NotificationExpansionState: ObservableObject {
    @Published var rows: Set<String> = []
    @Published var groups: Set<String> = []

    func row(_ key: String) -> Binding<Bool> { binding(key, in: \.rows) }
    func group(_ key: String) -> Binding<Bool> { binding(key, in: \.groups) }

    private func binding(_ key: String, in path: ReferenceWritableKeyPath<NotificationExpansionState, Set<String>>) -> Binding<Bool> {
        Binding(get: { self[keyPath: path].contains(key) }, set: { expanded in
            if expanded { self[keyPath: path].insert(key) }
            else { self[keyPath: path].remove(key) }
        })
    }

    func retain(notices: [PhoneCheckCore.Notice]) {
        let retainedRows = rows.intersection(notices.map(\.key))
        let retainedGroups = groups.intersection(NotificationSection.sections(notices).map(\.id))
        if rows != retainedRows { rows = retainedRows }
        if groups != retainedGroups { groups = retainedGroups }
    }
}

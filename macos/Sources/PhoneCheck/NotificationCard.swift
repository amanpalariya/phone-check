import AppKit
import SwiftUI

private final class CardPresentation: ObservableObject {
    @Published var hovering = false
    @Published var translation: CGFloat = 0
}

/// Presentation only: the row remains visible until Android confirms removal.
struct NotificationCard: ViewModifier {
    let canDismiss: Bool
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var presentation = CardPresentation()
    @FocusState private var closeFocused: Bool
    private let threshold: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if canDismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(.background.opacity(0.8), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focused($closeFocused)
                    .accessibilityLabel("Dismiss on phone")
                    .help("Dismiss on phone")
                    .opacity(presentation.hovering || closeFocused ? 1 : 0.65)
                    .padding(8)
                }
            }
            .offset(x: reduceMotion ? 0 : presentation.translation)
            .background(alignment: presentation.translation < 0 ? .trailing : .leading) {
                if canDismiss && abs(presentation.translation) > 6 && !reduceMotion {
                    Label("Dismiss on phone", systemImage: "xmark")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .opacity(min(1, Double(abs(presentation.translation) / threshold)))
                }
            }
            .background {
                TrackpadDismissal(enabled: canDismiss, changed: { presentation.translation = $0 }, ended: finishSwipe)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onHover { presentation.hovering = $0 }
            .onChange(of: canDismiss) { _, _ in presentation.translation = 0 }
            .accessibilityActions {
                if canDismiss { Button("Dismiss on phone", action: dismiss) }
            }
    }

    private func finishSwipe(_ distance: CGFloat) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { presentation.translation = 0 }
        if canDismiss && abs(distance) >= threshold { dismiss() }
    }
}

/// SwiftUI drag gestures cover click-and-drag; trackpad swipes arrive as scroll events.
/// Observe only this card's window/bounds and leave vertical scrolling untouched.
private struct TrackpadDismissal: NSViewRepresentable {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeView { SwipeView() }
    func updateNSView(_ view: SwipeView, context: Context) {
        view.enabled = enabled
        view.changed = changed
        view.ended = ended
    }
    static func dismantleNSView(_ view: SwipeView, coordinator: ()) { view.stop() }

    final class SwipeView: NSView {
        var enabled = false
        var changed: (CGFloat) -> Void = { _ in }
        var ended: (CGFloat) -> Void = { _ in }
        private var monitor: Any?
        private var horizontal: Bool?
        private var distance: CGFloat = 0
        private var verticalDistance: CGFloat = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            horizontal = nil; distance = 0; verticalDistance = 0
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === window else { return event }
            if event.phase.contains(.began) {
                horizontal = nil; distance = 0; verticalDistance = 0
            }
            // Momentum must never dismiss another card after a completed swipe.
            guard event.momentumPhase.isEmpty else { return event }
            guard enabled, event.hasPreciseScrollingDeltas, !event.phase.isEmpty else { return event }
            if horizontal == nil {
                guard visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return event }
            }
            distance += event.scrollingDeltaX
            verticalDistance += event.scrollingDeltaY
            if horizontal == nil && max(abs(distance), abs(verticalDistance)) > 6 {
                horizontal = abs(distance) > abs(verticalDistance) * 1.5
            }
            let consumed = horizontal == true
            if event.phase.contains(.cancelled) || event.phase.contains(.ended) {
                if consumed { ended(event.phase.contains(.cancelled) ? 0 : distance) }
                horizontal = nil; distance = 0; verticalDistance = 0
            } else if consumed {
                changed(max(-120, min(120, distance)))
            }
            return consumed ? nil : event
        }
    }
}

import AppKit
import SwiftUI

private final class CardPresentation: ObservableObject {
    @Published var translation: CGFloat = 0
    #if PHONECHECK_VISUAL_TEST
    @Published var hovering = CommandLine.arguments.contains("--hover")
    #else
    @Published var hovering = false
    #endif
}

/// Presentation only: the row remains visible until Android confirms removal.
struct NotificationCard: ViewModifier {
    let canDismiss: Bool
    let dismiss: () -> Void
    var surface = true
    var stackDepth = 0
    var swipeToDismiss = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var presentation = CardPresentation()
    @FocusState private var closeFocused: Bool
    private var showClose: Bool { presentation.hovering || closeFocused }
    private let threshold: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .background {
                if surface {
                    ZStack {
                        if stackDepth > 1 {
                            NotificationStackEdge(offset: 12)
                        }
                        if stackDepth > 0 {
                            NotificationStackEdge(offset: 6)
                        }
                        NotificationSurface()
                    }
                }
            }
            .padding(6)
            .overlay(alignment: .topTrailing) {
                if canDismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 24, height: 24)
                            .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss on phone")
                    .help("Dismiss on phone")
                    .focused($closeFocused)
                    .opacity(showClose ? 1 : 0)
                    .allowsHitTesting(showClose)
                }
            }
            .padding(.bottom, CGFloat(min(2, stackDepth)) * 6)
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
                TrackpadDismissal(enabled: canDismiss && swipeToDismiss, changed: { presentation.translation = $0 }, ended: finishSwipe)
            }
            .contentShape(Rectangle())
            .onHover { presentation.hovering = $0 }
            .onChange(of: canDismiss) { _, _ in presentation.translation = 0 }
            .accessibilityActions {
                if canDismiss { Button("Dismiss on phone", action: dismiss) }
            }
    }

    private func finishSwipe(_ distance: CGFloat) {
        withAnimation(NotificationMotion.animation(reduceMotion: reduceMotion)) { presentation.translation = 0 }
        if canDismiss && abs(distance) >= threshold { dismiss() }
    }
}

/// Only the exposed rear edge is drawn. The front card sees the same backdrop
/// as a single notification, without another glass surface underneath it.
private struct NotificationStackEdge: View {
    let offset: CGFloat
    private var radius: CGFloat {
        if #available(macOS 26.0, *) { return 20 }
        return 16
    }

    var body: some View {
        NotificationSurface()
            .padding(.horizontal, offset)
            .offset(y: offset)
            .mask {
                GeometryReader { proxy in
                    Path { path in
                        path.addRect(CGRect(origin: .zero,
                                            size: CGSize(width: proxy.size.width, height: proxy.size.height + offset)))
                        path.addPath(RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .path(in: CGRect(origin: .zero, size: proxy.size)))
                    }.fill(style: FillStyle(eoFill: true))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// SwiftUI drag gestures cover click-and-drag; trackpad swipes arrive as scroll events.
/// Observe only this card's window/bounds and leave vertical scrolling untouched.
private struct TrackpadDismissal: NSViewRepresentable {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.identifier = NSUserInterfaceItemIdentifier("notification-card-swipe")
        return view
    }
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


/// Shared surface for notification cards and the compact pane controls.
struct NotificationSurface: View {
    var pointerOffset: CGFloat? = nil

    var body: some View {
        if let pointerOffset {
            let shape = NotificationPointerShape(offset: pointerOffset)
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
        } else if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
        }
    }
}

/// A single outline keeps the pointer and card in the same material surface.
struct NotificationPointerShape: Shape {
    static let height: CGFloat = 12
    var offset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + Self.height
        let radius: CGFloat = min(20, rect.width / 4, (rect.height - Self.height) / 2)
        let center = min(max(rect.midX + offset, rect.minX + radius + 20), rect.maxX - radius - 20)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        // Horizontal tangents at the shoulders and crest avoid a sharp notch.
        path.addLine(to: CGPoint(x: center - 20, y: top))
        path.addCurve(to: CGPoint(x: center, y: rect.minY),
                      control1: CGPoint(x: center - 10, y: top),
                      control2: CGPoint(x: center - 7, y: rect.minY))
        path.addCurve(to: CGPoint(x: center + 20, y: top),
                      control1: CGPoint(x: center + 7, y: rect.minY),
                      control2: CGPoint(x: center + 10, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + radius),
                          control: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: top),
                          control: CGPoint(x: rect.minX, y: top))
        path.closeSubpath()
        return path
    }
}

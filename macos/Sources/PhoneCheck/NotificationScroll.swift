import AppKit
import SwiftUI

/// Use AppKit's overlay scroller so the compact feed has equal side margins.
/// The scroll indicator must not reserve a column or resize notification content.
struct NotificationScroll<Content: View>: NSViewRepresentable {
    let contentHeight: CGFloat
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var height: NSLayoutConstraint?
    }

    private func hostedContent(_ context: Context) -> AnyView {
        AnyView(content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.colorScheme, context.environment.colorScheme)
            .environment(\.controlActiveState, context.environment.controlActiveState)
            .environment(\.appearsActive, context.environment.appearsActive))
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NotificationOverlayScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let host = NSHostingView(rootView: hostedContent(context))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        let height = host.heightAnchor.constraint(equalToConstant: max(1, contentHeight))
        context.coordinator.height = height
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            host.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            height
        ])
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let origin = scroll.contentView.bounds.origin
        (scroll.documentView as? NSHostingView<AnyView>)?.rootView = hostedContent(context)
        context.coordinator.height?.constant = max(1, contentHeight)
        scroll.layoutSubtreeIfNeeded()
        // AppKit's implicit document resizing can anchor to the bottom while a
        // row expands. Keep the viewport in place and allow the full new height.
        let maxY = max(0, contentHeight - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, origin.y), maxY)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

final class NotificationOverlayScrollView: NSScrollView {
    private let bottomFade = CAGradientLayer()
    private(set) var hasMoreBelow = false

    override func layout() {
        super.layout()
        updateBottomFade()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateBottomFade()
    }

    private func updateBottomFade() {
        guard let documentView else { return }
        let visible = documentVisibleRect
        hasMoreBelow = documentView.isFlipped
            ? visible.maxY < documentView.bounds.maxY - 1
            : visible.minY > documentView.bounds.minY + 1
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        guard hasMoreBelow, contentView.bounds.height > 0 else {
            contentView.layer?.mask = nil
            return
        }
        guard let layer = contentView.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bottomFade.frame = layer.bounds
        bottomFade.startPoint = CGPoint(x: 0.5, y: 0)
        bottomFade.endPoint = CGPoint(x: 0.5, y: 1)
        bottomFade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        bottomFade.locations = [0, NSNumber(value: max(0, 1 - 32 / layer.bounds.height)), 1]
        layer.mask = bottomFade
        CATransaction.commit()
    }

    // AppKit can reapply the system preference after attaching to a window.
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
}

import AppKit
import SwiftUI

/// Use AppKit's overlay scroller so the compact feed has equal side margins.
/// The scroll indicator must not reserve a column or resize notification content.
struct NotificationScroll<Content: View>: View {
    let contentHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @StateObject private var geometry = NotificationScrollGeometry()

    var body: some View {
        NotificationScrollBridge(contentHeight: contentHeight, geometry: geometry, content: content)
            .background {
                AnimatedDocumentHeight(height: contentHeight, geometry: geometry)
            }
    }
}

/// Only this lightweight leaf is evaluated on animation frames. Updating the
/// document extent must not replace or force-layout the entire SwiftUI feed.
private struct AnimatedDocumentHeight: View, Animatable {
    var height: CGFloat
    let geometry: NotificationScrollGeometry
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }
    var body: some View { DocumentHeightBridge(height: height, geometry: geometry) }
}

private struct DocumentHeightBridge: NSViewRepresentable {
    let height: CGFloat
    let geometry: NotificationScrollGeometry
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { geometry.resize(to: height) }
}

private final class NotificationScrollGeometry: ObservableObject {
    weak var scroll: NotificationOverlayScrollView?

    func resize(to height: CGFloat) {
        guard let scroll, let document = scroll.documentView, height.isFinite else { return }
        let height = max(1, height)
        guard abs(document.frame.height - height) > 0.01 else { return }
        let origin = scroll.contentView.bounds.origin
        document.setFrameSize(NSSize(width: scroll.contentSize.width, height: height))
        scroll.restoreViewport(origin)
    }
}

/// Keep one SwiftUI root alive for the lifetime of the scroll view. Replacing
/// NSHostingView.rootView can replace rendered card surfaces while native
/// descendants still report interpolated frames, concealing a transition reset.
private final class NotificationHostedContent: ObservableObject {
    @Published var view: AnyView
    init(view: AnyView) { self.view = view }
}

private struct NotificationHostedRoot: View {
    @ObservedObject var content: NotificationHostedContent
    var body: some View { content.view }
}

/// The hosting view always receives the destination content size. A separate
/// flipped document supplies the animated scroll extent. In particular, AppKit
/// must never center an oversized hosting root inside a shorter animated frame.
private final class NotificationDocumentView: NSView {
    let host: NSHostingView<AnyView>
    let content: NotificationHostedContent
    var layoutHeight: CGFloat { didSet { layoutHost() } }
    override var isFlipped: Bool { true }

    init(root: AnyView, height: CGFloat) {
        let content = NotificationHostedContent(view: root)
        self.content = content
        host = NSHostingView(rootView: AnyView(NotificationHostedRoot(content: content)))
        layoutHeight = max(1, height)
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: layoutHeight))
        host.sizingOptions = []
        addSubview(host)
        layoutHost()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = frame.width != newSize.width
        super.setFrameSize(newSize)
        if widthChanged { layoutHost() }
    }

    private func layoutHost() {
        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: layoutHeight)
        if host.frame != rect { host.frame = rect }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct NotificationScrollBridge<Content: View>: NSViewRepresentable {
    let contentHeight: CGFloat
    let geometry: NotificationScrollGeometry
    @ViewBuilder let content: () -> Content

    private func hostedContent(_ context: Context) -> AnyView {
        AnyView(content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.colorScheme, context.environment.colorScheme)
            .environment(\.controlActiveState, context.environment.controlActiveState)
            .environment(\.appearsActive, context.environment.appearsActive))
    }

    func makeNSView(context: Context) -> NotificationOverlayScrollView {
        let scroll = NotificationOverlayScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let document = NotificationDocumentView(root: hostedContent(context), height: contentHeight)
        document.autoresizingMask = [.width]
        scroll.documentView = document
        geometry.scroll = scroll
        return scroll
    }

    func updateNSView(_ scroll: NotificationOverlayScrollView, context: Context) {
        guard let document = scroll.documentView as? NotificationDocumentView else { return }
        withTransaction(context.transaction) {
            document.content.view = hostedContent(context)
            document.layoutHeight = max(1, contentHeight)
        }
    }
}

final class NotificationOverlayScrollView: NSScrollView {
    private let edgeFade = CAGradientLayer()
    private(set) var hasMoreAbove = false
    private(set) var hasMoreBelow = false

    override func layout() {
        let origin = contentView.bounds.origin
        super.layout()
        restoreViewport(origin)
    }

    func restoreViewport(_ origin: NSPoint) {
        let maxY = max(0, (documentView?.frame.height ?? 0) - contentView.bounds.height)
        let pinned = NSPoint(x: 0, y: min(max(0, origin.y), maxY))
        if contentView.bounds.origin != pinned { contentView.scroll(to: pinned) }
        reflectScrolledClipView(contentView)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateEdgeFade()
    }

    private func updateEdgeFade() {
        guard let documentView else { return }
        let visible = documentVisibleRect
        hasMoreAbove = documentView.isFlipped
            ? visible.minY > documentView.bounds.minY + 1
            : visible.maxY < documentView.bounds.maxY - 1
        hasMoreBelow = documentView.isFlipped
            ? visible.maxY < documentView.bounds.maxY - 1
            : visible.minY > documentView.bounds.minY + 1
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        guard hasMoreAbove || hasMoreBelow, contentView.bounds.height > 0 else {
            contentView.layer?.mask = nil
            return
        }
        guard let layer = contentView.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fade = min(0.5, 32 / layer.bounds.height)
        edgeFade.frame = layer.bounds
        edgeFade.startPoint = CGPoint(x: 0.5, y: 0)
        edgeFade.endPoint = CGPoint(x: 0.5, y: 1)
        edgeFade.colors = [
            hasMoreAbove ? NSColor.clear.cgColor : NSColor.black.cgColor,
            NSColor.black.cgColor, NSColor.black.cgColor,
            hasMoreBelow ? NSColor.clear.cgColor : NSColor.black.cgColor
        ]
        edgeFade.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
        layer.mask = edgeFade
        CATransaction.commit()
    }

    // AppKit can reapply the system preference after attaching to a window.
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
}

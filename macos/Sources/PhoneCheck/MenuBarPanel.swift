import AppKit
import SwiftUI
import Combine

// Host one native glass surface in a transparent utility window. An additional
// opaque window background would obscure the material behind it.
final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

final class MenuBarPresentation {
    private let panel: MenuBarPanel
    private let hosting: NSHostingView<MenuSurface>
    private weak var anchor: NSStatusBarButton?
    private var changes: AnyCancellable?
    private var outsideClick: Any?
    private var deactivate: NSObjectProtocol?
    private var resizeScheduled = false
    var isShown: Bool { panel.isVisible }

    init(model: Companion, anchor: NSStatusBarButton) {
        self.anchor = anchor
        hosting = NSHostingView(rootView: MenuSurface(model: model, activeUtility: true))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel = MenuBarPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        panel.contentView = hosting
        changes = model.objectWillChange.sink { [weak self] _ in
            guard let self, !self.resizeScheduled else { return }
            self.resizeScheduled = true
            DispatchQueue.main.async {
                self.resizeScheduled = false
                self.resizeAndPosition()
            }
        }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
        deactivate = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                guard !NSApp.isActive, NSApp.currentEvent?.type != .leftMouseDown else { return }
                self?.close()
            }
        }
    }
    deinit {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        if let deactivate { NotificationCenter.default.removeObserver(deactivate) }
    }
    func show() {
        resizeAndPosition()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func close() { panel.orderOut(nil) }
    private func resizeAndPosition() {
        guard let anchor, let window = anchor.window else { return }
        let size = hosting.fittingSize
        panel.setContentSize(NSSize(width: 336, height: max(100, ceil(size.height))))
        hosting.layoutSubtreeIfNeeded()
        let button = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(visible.minX + 8, button.midX - panel.frame.width / 2), visible.maxX - panel.frame.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: button.minY - panel.frame.height - 6))
    }
}

struct MenuSurface: View {
    @ObservedObject var model: Companion
    var activeUtility = false
    @ViewBuilder var body: some View {
        if activeUtility {
            // The transient AppKit panel is outside a SwiftUI Scene. It closes on
            // deactivation; use key-window rendering while its controls are visible.
            surface.environment(\.appearsActive, true).environment(\.controlActiveState, .key)
        } else {
            surface
        }
    }
    @ViewBuilder private var surface: some View {
        if #available(macOS 26.0, *) {
            CompanionView(model: model)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            CompanionView(model: model)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

import AppKit
import Combine
import SwiftUI
import PhoneCheckCore

/// Own the menu-bar entry and a borderless surface, rather than an NSPopover.
/// Notification state and command confirmation remain in the existing models.
final class NotificationPaneController: NSObject, NSWindowDelegate {
    private let model: Companion
    private let testbed: NotificationTestbed
    private let statusItem: NSStatusItem
    private var panel: NotificationPanel?
    private var testbedWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var trackingMenu = false

    init(model: Companion, testbed: NotificationTestbed) {
        self.model = model
        self.testbed = testbed
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        Publishers.Merge(model.objectWillChange, testbed.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .init("PhoneCheckShow"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.show() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self, panel?.isVisible == true else { return }
                show()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.trackingMenu = true }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in self?.trackingMenu = false }.store(in: &subscriptions)
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let samples = testbed.showsInPane
        let count = samples ? NotificationSection.count(testbed.notices) : model.notificationCount
        button.image = NSImage(systemSymbolName: samples ? "testtube.2" : "iphone", accessibilityDescription: nil)
        button.image?.isTemplate = true
        button.title = samples || model.connected ? " \(count)" : ""
        button.setAccessibilityLabel("Phone Check, \(samples ? "Testbed" : model.status), \(count) notifications")
        button.toolTip = "Phone Check"
    }

    @objc private func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let anchor = statusItem.button.flatMap { button in
            button.window?.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let frame = NotificationPaneLayout.frame(in: screen.visibleFrame, anchor: anchor)
        let panel: NotificationPanel
        if let existing = self.panel { panel = existing }
        else {
            panel = NotificationPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.title = "Phone Check notifications"
            panel.setAccessibilityLabel("Phone Check notifications")
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.delegate = self
            panel.dismiss = { [weak self] in self?.hide() }
            self.panel = panel
        }
        panel.setFrame(frame, display: false)
        // Reuse the hosting tree when reopening so expanded rows and reply drafts survive.
        if let surface = panel.contentView as? NotificationPaneSurface {
            surface.host.rootView = root(height: frame.height)
        } else {
            panel.contentView = NotificationPaneSurface(frame: NSRect(origin: .zero, size: frame.size),
                                                       root: root(height: frame.height))
        }
        panel.makeKeyAndOrderFront(nil)
        // Start with no search focus; Tab and clicking still enter native editors.
        panel.makeFirstResponder(panel.contentView)
        installMonitors()
    }

    private func root(height: CGFloat) -> AnyView {
        AnyView(CompanionView(model: model, testbed: testbed, showTestbed: { [weak self] in self?.showTestbed() },
                              feedMaximumHeight: max(60, height - 190))
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
    }

    func hide() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, panel?.attachedSheet == nil, !trackingMenu else { return }
        hide()
    }

    private func installMonitors() {
        removeMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== panel && event.window !== statusItem.button?.window && panel?.attachedSheet == nil && !trackingMenu {
                hide()
            }
            return event
        }
    }

    private func removeMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil; localMonitor = nil
    }

    private func showTestbed() {
        hide()
        if testbedWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 581, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Notification Testbed"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: NotificationTestbedView(model: testbed))
            window.center()
            testbedWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        testbedWindow?.makeKeyAndOrderFront(nil)
    }

    deinit {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

/// Screen coordinates include negative origins on secondary displays.
enum NotificationPaneLayout {
    static func frame(in visibleFrame: NSRect, anchor: NSRect?) -> NSRect {
        // Before AppKit lays out the status item, its window can still be at (0, 0).
        // Ignore that provisional rectangle rather than creating a zero-height panel.
        let anchor = anchor.flatMap { rect -> NSRect? in
            guard rect.width > 0, rect.maxX >= visibleFrame.minX, rect.minX <= visibleFrame.maxX,
                  abs(rect.minY - visibleFrame.maxY) <= 40 else { return nil }
            return rect
        }
        let width = min(388, visibleFrame.width)
        let top = min(visibleFrame.maxY, anchor.map { $0.minY - 6 } ?? visibleFrame.maxY)
        let height = min(680, max(0, top - visibleFrame.minY))
        let center = anchor?.midX ?? visibleFrame.midX
        let x = min(max(visibleFrame.minX, center - width / 2), visibleFrame.maxX - width)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }
}

final class NotificationPanel: NSPanel {
    var dismiss: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, attachedSheet == nil {
            dismiss()
            return
        }
        super.sendEvent(event)
    }
}

/// A native behind-window blur with softly feathered edges. No enclosing card,
/// border, title bar or window shadow. Each notification supplies its own surface.
final class NotificationPaneSurface: NSView {
    let host: NSHostingView<AnyView>
    let backdrop: NSView
    private let feather = CALayer()
    private var appearanceSubscription: AnyCancellable?
    private var accessibilitySubscription: AnyCancellable?
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, root: AnyView) {
        host = NSHostingView(rootView: root)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.cornerRadius = 0
            backdrop = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            backdrop = material
        }
        super.init(frame: frame)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.frame = bounds
        // Feather the actual backdrop, including its tint and edge highlights.
        // A standalone gradient over the window would only fade a colored sheet.
        let mask = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            NSGradient(colorsAndLocations: (NSColor.clear, 0), (NSColor.black, 0.08),
                       (NSColor.black, 0.92), (NSColor.clear, 1))!.draw(in: rect, angle: 0)
            let vertical = NSImage(size: rect.size, flipped: false) { bounds in
                NSGradient(colorsAndLocations: (NSColor.clear, 0), (NSColor.black, 0.04),
                           (NSColor.black, 0.96), (NSColor.clear, 1))!.draw(in: bounds, angle: 90)
                return true
            }
            vertical.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        if let material = backdrop as? NSVisualEffectView {
            material.maskImage = mask
        } else {
            backdrop.wantsLayer = true
            feather.contents = mask.cgImage(forProposedRect: nil, context: nil, hints: nil)
            feather.frame = backdrop.bounds
            backdrop.layer?.mask = feather
        }
        addSubview(backdrop)
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        appearanceSubscription = NotificationAppearance.shared.$transparency
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateTransparency($0) }
        accessibilitySubscription = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in self?.updateTransparency(NotificationAppearance.shared.transparency) }
        updateTransparency(NotificationAppearance.shared.transparency)
    }

    private func updateTransparency(_ value: Double) {
        backdrop.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 1 - value
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        feather.frame = backdrop.bounds
        CATransaction.commit()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

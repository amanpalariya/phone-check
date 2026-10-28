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
                              feedMaximumHeight: max(60, height - 220),
                              contentHeightChanged: { [weak self] height in
                                  (self?.panel?.contentView as? NotificationPaneSurface)?.setContentHeight(height)
                              })
            .padding(.top, 32)
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
        let width = min(444, visibleFrame.width)
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

/// Localized backdrop, independent of the cards: native blur plus a soft dimming wash.
/// Its extent follows the visible content rather than filling the entire panel.
final class NotificationPaneSurface: NSView {
    let host: NSHostingView<AnyView>
    let backdrop = NSVisualEffectView()
    private let dimming = NSImageView()
    private var contentHeight: CGFloat = 240
    private var appearanceSubscription: AnyCancellable?
    private var accessibilitySubscription: AnyCancellable?
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, root: AnyView) {
        host = NSHostingView(rootView: root)
        super.init(frame: frame)
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        addSubview(backdrop)
        dimming.imageScaling = .scaleAxesIndependently
        dimming.setAccessibilityElement(false)
        addSubview(dimming)
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        appearanceSubscription = NotificationAppearance.shared.$transparency
            .combineLatest(NotificationAppearance.shared.$usesSystemBackdrop)
            .receive(on: RunLoop.main)
            .sink { [weak self] transparency, system in
                self?.updateStrength(transparency: transparency, system: system)
            }
        accessibilitySubscription = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in self?.refreshAppearance() }
        layoutBackdrop()
        refreshAppearance()
    }

    func setContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0, abs(contentHeight - height) > 1 else { return }
        contentHeight = height
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutBackdrop()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        // Notification Center's surrounding wash stays dark in both appearances.
        // Only the backdrop is overridden; notification cards retain the system style.
        backdrop.appearance = NSAppearance(named: .darkAqua)
        updateStrength(transparency: NotificationAppearance.shared.transparency,
                       system: NotificationAppearance.shared.usesSystemBackdrop)
    }

    private func updateStrength(transparency: Double, system: Bool) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            backdrop.alphaValue = 1
            dimming.alphaValue = 0
            return
        }
        let strength = system ? 1 : 1 - transparency
        backdrop.alphaValue = 0.32 * strength
        dimming.alphaValue = 0.22 * strength
    }

    private func layoutBackdrop() {
        // Leave 32 points above the content and 64 below for the soft falloff.
        let height = min(bounds.height, contentHeight + 96)
        let rect = NSRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
        guard rect.width > 0, rect.height > 0 else { return }
        guard backdrop.frame != rect || backdrop.maskImage == nil else { return }
        backdrop.frame = rect
        dimming.frame = rect
        let mask = Self.featheredMask(size: rect.size)
        backdrop.maskImage = mask
        dimming.image = NSImage(size: rect.size, flipped: false) { bounds in
            NSColor.black.setFill()
            bounds.fill()
            mask.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }

    private static func featheredMask(size: NSSize) -> NSImage {
        // Keep the fade in points, so short lists don't acquire sharp edges and
        // long lists don't get a larger blur field merely because they're taller.
        let x = min(72 / size.width, 0.48)
        let y = min(64 / size.height, 0.48)
        return NSImage(size: size, flipped: false) { rect in
            func gradient(_ edge: CGFloat) -> NSGradient {
                NSGradient(colorsAndLocations: (.clear, 0), (.black.withAlphaComponent(0.25), edge * 0.35),
                           (.black.withAlphaComponent(0.75), edge * 0.7), (.black, edge),
                           (.black, 1 - edge), (.black.withAlphaComponent(0.75), 1 - edge * 0.7),
                           (.black.withAlphaComponent(0.25), 1 - edge * 0.35), (.clear, 1))!
            }
            gradient(x).draw(in: rect, angle: 0)
            let vertical = NSImage(size: size, flipped: false) { bounds in
                gradient(y).draw(in: bounds, angle: 90)
                return true
            }
            vertical.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

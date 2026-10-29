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
    private var settingsController: CompanionSettingsController?
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
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Phone Check")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Phone Check", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
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
            surface.host.rootView = root(height: frame.height, pointerOffset: (anchor?.midX ?? frame.midX) - frame.midX)
        } else {
            panel.contentView = NotificationPaneSurface(frame: NSRect(origin: .zero, size: frame.size),
                                                       root: root(height: frame.height, pointerOffset: (anchor?.midX ?? frame.midX) - frame.midX))
        }
        panel.makeKeyAndOrderFront(nil)
        // Start with no search focus; Tab and clicking still enter native editors.
        panel.makeFirstResponder(panel.contentView)
        installMonitors()
    }

    private func root(height: CGFloat, pointerOffset: CGFloat) -> AnyView {
        AnyView(CompanionView(model: model, testbed: testbed, showTestbed: { [weak self] in self?.showTestbed() },
                              showSettings: { [weak self] in self?.showSettings() },
                              pointerOffset: pointerOffset,
                              feedMaximumHeight: max(60, height - 220),
                              contentHeightChanged: { [weak self] height in
                                  (self?.panel?.contentView as? NotificationPaneSurface)?.setContentHeight(height)
                              })
            .padding(.top, NotificationPaneLayout.contentTopInset)
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

    @objc func showSettings() {
        hide()
        if settingsController == nil { settingsController = CompanionSettingsController(model: model) }
        settingsController?.show()
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
    static let contentTopInset: CGFloat = 2
    static func frame(in visibleFrame: NSRect, anchor: NSRect?) -> NSRect {
        // Before AppKit lays out the status item, its window can still be at (0, 0).
        // Ignore that provisional rectangle rather than creating a zero-height panel.
        let anchor = anchor.flatMap { rect -> NSRect? in
            guard rect.width > 0, rect.maxX >= visibleFrame.minX, rect.minX <= visibleFrame.maxX,
                  abs(rect.minY - visibleFrame.maxY) <= 40 else { return nil }
            return rect
        }
        let width = min(444, visibleFrame.width)
        let top = min(visibleFrame.maxY, anchor.map { $0.minY - 2 } ?? visibleFrame.maxY)
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
        if event.type == .scrollWheel, let contentView {
            var target = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil))
            while let view = target {
                if view is NSScrollView { super.sendEvent(event); return }
                target = view.superview
            }
            // Empty backdrop space owns its scroll events; never pass them on
            // to a different window or the application underneath the pane.
            return
        }
        super.sendEvent(event)
    }
}

/// AppKit-managed behind-window blur stays below the SwiftUI notification tree.
/// A minimally drawn input surface prevents transparent gaps from scrolling apps
/// underneath the pane without changing any notification-card material.
final class NotificationPaneSurface: NSView {
    let host: NSHostingView<AnyView>
    let backdrop = NSVisualEffectView()
    let compositor = CompositorBackdrop(frame: .zero)
    private let inputSurface = NSView()
    private let fallbackFeather = BackdropFeather()
    private(set) var backdropMaskImage: NSImage?
    private let dimming = NSImageView()
#if PHONECHECK_VISUAL_TEST
    var suppressBackdropTint = false {
        didSet { refreshAppearance() }
    }
#endif
    private var contentHeight: CGFloat = 240
    private var maskTemplateSize = NSSize.zero
    private var appearanceSubscription: AnyCancellable?
    private var accessibilitySubscription: AnyCancellable?
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, root: AnyView) {
        host = NSHostingView(rootView: root)
        super.init(frame: frame)
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        inputSurface.wantsLayer = true
        inputSurface.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        inputSurface.setAccessibilityElement(false)
        addSubview(backdrop)
        addSubview(compositor)
        addSubview(inputSurface)
        dimming.imageScaling = .scaleAxesIndependently
        dimming.setAccessibilityElement(false)
        addSubview(dimming)
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        appearanceSubscription = NotificationAppearance.shared.$transparency
            .combineLatest(NotificationAppearance.shared.$usesSystemBackdrop, NotificationAppearance.shared.$blurAmount)
            .receive(on: RunLoop.main)
            .sink { [weak self] transparency, system, blur in
                self?.compositor.radius = blur
                self?.updateStrength(transparency: transparency, system: system)
            }
        accessibilitySubscription = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in self?.refreshAppearance() }
        layoutBackdrop()
        compositor.radius = NotificationAppearance.shared.blurAmount
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
        refreshAppearance()
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
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let native = compositor.isAvailable && !reduced
        backdrop.isHidden = native
        compositor.isHidden = !native
        if reduced {
            backdrop.alphaValue = 1
            dimming.alphaValue = 0
            return
        }
        let strength = 1 - transparency
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint = system ? (dark ? 0.10 : 0.08) : 0.08 + 0.32 * strength
        // Never crossfade filtered output with the sharp desktop. Strength
        // controls the dark wash; blur amount controls the background filter.
        compositor.alphaValue = 1
        backdrop.alphaValue = system ? 0.32 : 0.18 + 0.14 * strength
        dimming.alphaValue = tint
#if PHONECHECK_VISUAL_TEST
        if suppressBackdropTint { dimming.alphaValue = 0 }
#endif
    }

    private func layoutBackdrop() {
        // Follow the controls/list, leaving only the soft falloff below them.
        let height = min(bounds.height, contentHeight + NotificationPaneLayout.contentTopInset + 64)
        let rect = NSRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
        guard rect.width > 0, rect.height > 0 else { return }
        guard backdrop.frame != rect || backdropMaskImage == nil else { return }
        inputSurface.frame = rect
        backdrop.frame = rect
        dimming.frame = rect
        compositor.frame = rect
        // Rasterize only the fixed feathered edges. All three renderers stretch
        // the opaque center, so resizing a list does no full-surface image work.
        let templateSize = NSSize(width: min(160, rect.width), height: min(144, rect.height))
        if maskTemplateSize != templateSize {
            maskTemplateSize = templateSize
            let mask = Self.featheredMask(size: templateSize)
            mask.capInsets = NSEdgeInsets(top: min(64, templateSize.height * 0.48),
                                          left: min(72, templateSize.width * 0.48),
                                          bottom: min(64, templateSize.height * 0.48),
                                          right: min(72, templateSize.width * 0.48))
            mask.resizingMode = .stretch
            backdropMaskImage = mask
            compositor.maskImage = mask
            dimming.image = mask
        }
        fallbackFeather.apply(backdropMaskImage, to: backdrop.layer, bounds: backdrop.bounds)
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

import AppKit
import Combine
import SwiftUI
import PhoneCheckCore

/// Own the menu-bar entry and a borderless surface, rather than an NSPopover.
/// Notification state and command confirmation remain in the existing models.
final class NotificationPaneController: NSObject, NSWindowDelegate {
    private enum Presentation { case hidden, visible, closing }

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
    private var presentation = Presentation.hidden
    private var presentationRevision = 0
#if PHONECHECK_VISUAL_TEST
    var statusButtonForChecks: NSStatusBarButton { statusItem.button! }
#endif

    init(model: Companion, testbed: NotificationTestbed) {
        self.model = model
        self.testbed = testbed
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            if #available(macOS 27.0, *) {
                statusItem.expandedInterfaceDelegate = self
            } else {
                button.target = self
                button.action = #selector(toggle)
                button.sendAction(on: [.leftMouseDown])
            }
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
                guard let self, presentation == .visible else { return }
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
        switch presentation {
        case .hidden: show()
        case .visible: hide()
        case .closing: break
        }
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
        presentationRevision += 1
        presentation = .visible
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        updateStatusHighlight()
        // Start with no search focus; Tab and clicking still enter native editors.
        panel.makeFirstResponder(panel.contentView)
        installMonitors()
    }

    private func updateStatusHighlight() {
        // Modern AppKit owns the menu-bar selection through its session.
        if #available(macOS 27.0, *) { return }
        statusItem.button?.highlight(panel?.isVisible == true)
        // Restore the legacy highlight after AppKit's mouse-tracking loop ends.
        // Main-queue blocks can run inside that loop; default-mode work cannot.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            guard let self else { return }
            statusItem.button?.highlight(self.panel?.isVisible == true)
        }
    }

    private func root(height: CGFloat, pointerOffset: CGFloat) -> AnyView {
        AnyView(CompanionView(model: model, testbed: testbed,
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
        closePane(animated: true)
        if #available(macOS 27.0, *) { statusItem.expandedInterfaceSession?.cancel() }
    }

    private func closePane(animated: Bool) {
        guard presentation == .visible, let panel else { return }
        presentation = .closing
        presentationRevision += 1
        let revision = presentationRevision
        let finish = { [weak self, weak panel] in
            // A later show invalidates this close's animation completion.
            guard let self, self.presentationRevision == revision, self.presentation == .closing else { return }
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            self.presentation = .hidden
            self.updateStatusHighlight()
            self.removeMonitors()
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            finish()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard presentation == .visible, (notification.object as? NSWindow) === panel,
              panel?.attachedSheet == nil, !trackingMenu else { return }
        // Clicking the status button may resign key before its action runs.
        // Let that action own the toggle instead of closing and then reopening.
        if NSEvent.pressedMouseButtons != 0 && statusButtonContainsMouse { return }
        hide()
    }

    private var statusButtonContainsMouse: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let bounds = window.convertToScreen(button.convert(button.bounds, to: nil))
        return bounds.contains(NSEvent.mouseLocation)
    }

    private func installMonitors() {
        removeMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, !statusButtonContainsMouse else { return }
            hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            return handleDismissalMouseDown(event) ? nil : event
        }
    }

    /// Return true when the click dismisses our UI and must not also activate it.
    func handleDismissalMouseDown(_ event: NSEvent) -> Bool {
        guard presentation != .hidden, let panel, panel.attachedSheet == nil else { return false }
        if let button = statusItem.button, event.window === button.window,
           button.bounds.contains(button.convert(event.locationInWindow, from: nil)) {
            // Cancel the native session before this click can begin another one.
            hide()
            return true
        }
        if event.window === panel, let surface = panel.contentView as? NotificationPaneSurface {
            let point = surface.convert(event.locationInWindow, from: nil)
            guard !surface.contentFrame.contains(point) else { return false }
            // Feathered blur and unused window space are outside the cards.
            hide()
            return true
        }
        guard !trackingMenu else { return false }
        if event.window !== panel { hide() }
        return false
    }

    // A native begin callback can arrive after the click has already requested
    // dismissal. Keep that same click from reopening a closing or visible pane.
    func beginExpandedInterface(cancel: () -> Void) {
        guard presentation == .hidden else {
            closePane(animated: true)
            cancel()
            return
        }
        show()
    }

    private func removeMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil; localMonitor = nil
    }

    @objc func showSettings() {
        hide()
        if settingsController == nil {
            settingsController = CompanionSettingsController(model: model, showTestbed: { [weak self] in
                self?.showTestbed()
            })
        }
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

@available(macOS 27.0, *)
extension NotificationPaneController: NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        beginExpandedInterface { session.cancel() }
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        closePane(animated: animated)
    }
}

/// Screen coordinates include negative origins on secondary displays.
enum NotificationPaneLayout {
    static let contentWidth: CGFloat = 340
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
    private let inputFeather = BackdropFeather()
    private(set) var backdropMaskImage: NSImage?
    private let dimming = NSView()
    private let dimmingFeather = BackdropFeather()
#if PHONECHECK_VISUAL_TEST
    var suppressBackdropTint = false {
        didSet { refreshAppearance() }
    }
#endif
    private var contentHeight: CGFloat = 240
    var contentFrame: NSRect {
        let width = min(NotificationPaneLayout.contentWidth, bounds.width)
        let top = bounds.maxY - NotificationPaneLayout.contentTopInset
        let height = min(contentHeight, max(0, top - bounds.minY))
        return NSRect(x: bounds.midX - width / 2, y: top - height, width: width, height: height)
    }
    private var maskTemplateSize = NSSize.zero
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
        dimming.wantsLayer = true
        dimming.layer?.backgroundColor = NSColor.black.cgColor
        dimming.setAccessibilityElement(false)
        addSubview(dimming)
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
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
        updateStrength()
    }

    private func updateStrength() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let native = compositor.isAvailable && !reduced
        backdrop.isHidden = native
        compositor.isHidden = !native
        if reduced {
            backdrop.alphaValue = 1
            dimming.alphaValue = 0
            return
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint = dark ? 0.035 : 0.025
        // Keep one subtle default wash; accessibility settings still take priority.
        // Never crossfade filtered output with the sharp desktop.
        compositor.alphaValue = 1
        backdrop.alphaValue = 0.16
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
        // Rasterize only the fixed feathered edges. All backdrop layers stretch
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
        }
        fallbackFeather.apply(backdropMaskImage, to: backdrop.layer, bounds: backdrop.bounds)
        dimmingFeather.apply(backdropMaskImage, to: dimming.layer, bounds: dimming.bounds)
        // The input surface must fade too: even its 1% fill reveals a rectangle
        // over a white desktop when left outside the backdrop mask.
        inputFeather.apply(backdropMaskImage, to: inputSurface.layer, bounds: inputSurface.bounds)
    }

    private static func featheredMask(size: NSSize) -> NSImage {
        // Zero slope and curvature at each end avoid a visible seam where the
        // desktop starts blurring. Keep the falloff fixed in points as the
        // opaque center stretches, including on short notification lists.
        let horizontal = min(72, size.width * 0.48)
        let vertical = min(64, size.height * 0.48)
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        func falloff(_ distance: CGFloat, over extent: CGFloat) -> CGFloat {
            let t = min(1, max(0, distance / extent))
            let eased = t * t * t * (t * (t * 6 - 15) + 10)
            // Keep the outer wash faint, concentrating the effect near the cards.
            return eased * eased
        }
        let pixels = bitmap.bitmapData!
        for row in 0..<height {
            let y = CGFloat(row)
            let dy = max(0, 1 - min(y, CGFloat(height - 1) - y) / vertical)
            for column in 0..<width {
                let x = CGFloat(column)
                let dx = max(0, 1 - min(x, CGFloat(width - 1) - x) / horizontal)
                // A radial corner falloff avoids the rectangular contour made
                // by multiplying independent horizontal and vertical fades.
                let alpha = falloff(1 - hypot(dx, dy), over: 1)
                let offset = row * bitmap.bytesPerRow + column * 4
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = UInt8((255 * alpha).rounded())
            }
        }
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

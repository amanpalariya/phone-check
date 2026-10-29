import AppKit
import QuartzCore

/// Dedicated behind-window capture; notification cards retain their system glass.
/// SPI is restricted to tested macOS generations, with a public material fallback.
/// Capture groups and live hosting follow MaterialView's WindowConfigurator:
/// https://github.com/OskarGroth/MaterialView/blob/main/Sources/MaterialView/NSMaterialView.swift
/// Background pixels remain in WindowServer and are never read by this app.
final class CompositorBackdrop: NSVisualEffectView {
    private let capture: CALayer?
    private let container = CALayer()
    private let feather = BackdropFeather()
    private var featherImage: NSImage?
    private let captureGroup = "PhoneCheckBackdrop-" + UUID().uuidString
    private weak var configuredWindow: NSWindow?
    private var originalFlatten = true
    private var originalHosting = true
    private var originalColor: NSColor?
    private var registeredByUs = false
    var blurLayer: CALayer? { capture }
    var isAvailable: Bool { capture != nil }
    var radius: Double = 1 { didSet { updateFilter() } }
    override var material: NSVisualEffectView.Material { get { .headerView } set {} }
    override var blendingMode: NSVisualEffectView.BlendingMode { get { .behindWindow } set {} }
    override var maskImage: NSImage? {
        get { featherImage }
        set { featherImage = newValue; updateMask() }
    }

    override init(frame: NSRect) {
        let supported = (26...27).contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        capture = supported ? (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init() : nil
        super.init(frame: frame)
        // Host the compositor tree directly instead of allowing AppKit to
        // flatten it into a view backing store.
        layer = CALayer()
        wantsLayer = true
        super.state = .active
        super.blendingMode = .withinWindow
        super.material = .appearanceBased
        layerUsesCoreImageFilters = false
        setAccessibilityElement(false)
        guard let capture else { return }
        // Disable AppKit's stock material layers, keeping its backdrop view
        // registration. This renderer supplies only its own capture/filter.
        setValue(true, forKey: "clear")
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false
        container.setValue(true, forKey: "allowsGroupBlending")
        capture.setValue(true, forKey: "windowServerAware")
        capture.setValue(true, forKey: "allowsSubstituteColor")
        capture.setValue(false, forKey: "allowsInPlaceFiltering")
        capture.setValue(captureGroup, forKey: "groupName")
        capture.setValue("owningContext", forKey: "groupNamespace")
        capture.setValue(1.0, forKey: "scale")
        capture.setValue(8.0, forKey: "bleedAmount")
        capture.setValue(true, forKey: "allowsGroupBlending")
        capture.name = "Phone Check desktop backdrop"
        capture.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        container.addSublayer(capture)
        layer?.insertSublayer(container, at: 0)
        updateFilter()
    }

    private func updateFilter() {
        guard radius.isFinite, let capture,
              let factory = NSClassFromString("CAFilter") as? NSObject.Type,
              factory.responds(to: NSSelectorFromString("filterWithType:")),
              let filter = factory.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return }
        filter.setValue("PhoneCheckBackdropBlur", forKey: "name")
        filter.setValue(min(12, max(0, radius)) * 3, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capture.filters = [filter]
        CATransaction.commit()
    }

    @objc private func _shouldAutoFlattenLayerTree() -> Bool { false }

    override func updateLayer() {
        // Deliberate SPI boundary: clear mode plus a custom backdrop must not
        // let NSVisualEffectView recreate the stock material over this layer.
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit positions the hosted root layer in its parent's coordinates.
        // Only size our child layers here; resetting the root to local bounds
        // would move a short, top-aligned backdrop to the bottom of the pane.
        container.frame = bounds
        capture?.frame = container.bounds
        CATransaction.commit()
        updateMask()
    }

    private func updateMask() { feather.apply(featherImage, to: container, bounds: bounds) }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingScale()
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? 1
        layer?.contentsScale = scale
        container.contentsScale = scale
        capture?.contentsScale = scale
        needsLayout = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let old = configuredWindow, old !== newWindow {
            if registeredByUs, old.responds(to: NSSelectorFromString("_unregisterBackdropView:")) {
                old.perform(NSSelectorFromString("_unregisterBackdropView:"), with: self)
                registeredByUs = false
            }
            old.setValue(originalFlatten, forKey: "shouldAutoFlattenLayerTree")
            old.setValue(false, forKey: "canHostLayersInWindowServer")
            old.setValue(originalHosting, forKey: "canHostLayersInWindowServer")
            if let originalColor { old.backgroundColor = originalColor }
            configuredWindow = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard isAvailable, let window, configuredWindow !== window,
              window.responds(to: NSSelectorFromString("canHostLayersInWindowServer")) else { return }
        configuredWindow = window
        if window.responds(to: NSSelectorFromString("_registerBackdropView:")),
           window.responds(to: NSSelectorFromString("_registeredBackdropViews")) {
            let views = window.perform(NSSelectorFromString("_registeredBackdropViews"))?.takeUnretainedValue() as? [NSView] ?? []
            if !views.contains(where: { $0 === self }) {
                window.perform(NSSelectorFromString("_registerBackdropView:"), with: self)
                registeredByUs = true
            }
        }
        originalFlatten = window.value(forKey: "shouldAutoFlattenLayerTree") as? Bool ?? true
        originalHosting = window.value(forKey: "canHostLayersInWindowServer") as? Bool ?? true
        originalColor = window.backgroundColor
        window.setValue(false, forKey: "shouldAutoFlattenLayerTree")
        window.setValue(false, forKey: "canHostLayersInWindowServer")
        window.setValue(true, forKey: "canHostLayersInWindowServer")
        window.isOpaque = false
        window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        updateBackingScale()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Stretch a cached alpha template after filtering. NSVisualEffectView.maskImage
/// also changes its capture region and does not preserve this feathered result.
final class BackdropFeather {
    private let layer = CALayer()
    private var appliedImage: NSImage?

    func apply(_ image: NSImage?, to target: CALayer?, bounds: CGRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            target?.mask = nil
            appliedImage = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if appliedImage !== image {
            appliedImage = image
            layer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let insets = image.capInsets
            layer.contentsCenter = CGRect(x: insets.left / image.size.width, y: insets.bottom / image.size.height,
                width: max(0.001, 1 - (insets.left + insets.right) / image.size.width),
                height: max(0.001, 1 - (insets.top + insets.bottom) / image.size.height))
        }
        layer.contentsScale = target?.contentsScale ?? 1
        layer.frame = bounds
        target?.mask = layer
        CATransaction.commit()
    }
}

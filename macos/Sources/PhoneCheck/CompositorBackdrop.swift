import AppKit
import QuartzCore

/// Blur without the tint/refraction of a glass sheet. These compositor hooks are
/// undocumented; limit them to tested OS generations and retain a public fallback.
final class CompositorBackdrop: NSView {
    private let sample: CALayer?
    private let blur: NSObject?
    private let feather = CALayer()
    var isAvailable: Bool {
        sample != nil && blur != nil && (window?.responds(to: NSSelectorFromString("canHostLayersInWindowServer")) ?? true)
    }
    var radius: Double = 2 {
        didSet {
            if let blur {
                blur.setValue(min(12, max(0, radius)), forKey: "inputRadius")
                sample?.filters = [blur]
            }
        }
    }
    var maskImage: NSImage? {
        didSet {
            feather.contents = maskImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            layer?.mask = maskImage == nil ? nil : feather
        }
    }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if (26...27).contains(major),
           let type = NSClassFromString("CABackdropLayer") as? CALayer.Type,
           let factory = NSClassFromString("CAFilter") as? NSObject.Type,
           factory.responds(to: NSSelectorFromString("filterWithType:")),
           let filter = factory.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject {
            let layer = type.init()
            let selectors = ["setWindowServerAware:", "setAllowsSubstituteColor:", "setAllowsInPlaceFiltering:"]
            if selectors.allSatisfy({ layer.responds(to: NSSelectorFromString($0)) }) {
                layer.setValue(true, forKey: "windowServerAware")
                // Keep protected-content substitution enabled; never read captured pixels.
                layer.setValue(true, forKey: "allowsSubstituteColor")
                layer.setValue(false, forKey: "allowsInPlaceFiltering")
                filter.setValue(2.0, forKey: "inputRadius")
                filter.setValue(true, forKey: "inputNormalizeEdges")
                layer.filters = [filter]
                sample = layer
                blur = filter
            } else {
                sample = nil; blur = nil
            }
        } else {
            sample = nil; blur = nil
        }
        super.init(frame: frame)
        wantsLayer = true
        if let sample { layer?.addSublayer(sample) }
        setAccessibilityElement(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard isAvailable, let window else { return }
        // The getter is available even on systems without an exposed setter; KVC
        // supplies the backing flag used by AppKit's own backdrop windows.
        guard window.responds(to: NSSelectorFromString("canHostLayersInWindowServer")) else {
            isHidden = true
            return
        }
        window.isOpaque = false
        window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        window.setValue(false, forKey: "shouldAutoFlattenLayerTree")
        window.setValue(false, forKey: "canHostLayersInWindowServer")
        window.setValue(true, forKey: "canHostLayersInWindowServer")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sample?.frame = bounds
        feather.frame = bounds
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

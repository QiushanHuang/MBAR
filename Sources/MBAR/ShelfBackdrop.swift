import AppKit
import MBARCore

/// Material container shared by the floating panel and the in-window appearance preview.
@MainActor final class ShelfBackdrop: NSView {
    let content: NSView
    private let blendingMode: NSVisualEffectView.BlendingMode
    private let tintWash = NSView()
    private var configuration: ShelfAppearance
    private var activeMaterial: ShelfMaterial?
    private var surface: NSView?

    init(frame: NSRect, configuration: ShelfAppearance, content: NSView,
         blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.configuration = configuration
        self.content = content
        self.blendingMode = blendingMode
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        tintWash.wantsLayer = true
        tintWash.setAccessibilityElement(false)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshMaterial),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        refreshMaterial()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ configuration: ShelfAppearance) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        refreshMaterial()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if surface != nil { refreshMaterial() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateShelfWindowShadow()
    }

    private func updateShelfWindowShadow() {
        guard blendingMode == .behindWindow, let window, window.contentView === self else { return }
        // With a hollow glass rim, WindowServer casts the window's drop shadow
        // into the transparent center as well as outside it.
        let needsShadow = activeMaterial?.usesGlassForeground != true
        if window.hasShadow != needsShadow { window.hasShadow = needsShadow }
    }

    @objc private func refreshMaterial() {
        let workspace = NSWorkspace.shared
        let reduced = workspace.accessibilityDisplayShouldReduceTransparency
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        var material: ShelfMaterial = reduced ? .translucent : configuration.material
        if #unavailable(macOS 26) {
            if material == .liquid || material.usesGlassForeground { material = .frosted }
        }
        let isGlass = material == .liquid || material.usesGlassForeground
        if activeMaterial != material { install(material) }
        updateShelfWindowShadow()
        updateCorners()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base = NSColor(srgbRed: dark ? 0.13 : 0.97, green: dark ? 0.14 : 0.97,
                           blue: dark ? 0.16 : 0.98, alpha: 1)
        let tint = NSColor(srgbRed: configuration.tint.red, green: configuration.tint.green,
                           blue: configuration.tint.blue, alpha: 1)
        let strength = CGFloat(configuration.intensity)
        let border = dark ? NSColor.white : NSColor.black
        let clearGlass = material.usesGlassForeground
        let outline = clearGlass ? layer : surface?.layer
        if !clearGlass { layer?.borderWidth = 0 }
        outline?.borderWidth = contrast && material != .quietGlass ? 1 : (isGlass ? 0 : 0.5)
        outline?.borderColor = border.withAlphaComponent(contrast ? 0.6 : (dark ? 0.25 : 0.16)).cgColor
        // The glass stays transparent between glyphs when the configured tint is zero.
        layer?.backgroundColor = material == .appleGlass && strength > 0 ? tint.withAlphaComponent(strength * 0.30).cgColor : nil
        let opticalAppearance = NSAppearance(named: contrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
        if clearGlass {
            // System ink follows the window. Other glass treatments use the source glass's appearance.
            surface?.appearance = configuration.iconTreatment == .system ? nil : opticalAppearance
        }
        let needsHalo = material == .translucent && !reduced && !contrast && configuration.opacity < 0.62
        if needsHalo {
            // A narrow halo stays with the glyphs as the desktop behind a low-opacity panel changes.
            let halo = NSShadow()
            halo.shadowOffset = .zero
            halo.shadowBlurRadius = 1.5
            halo.shadowColor = (dark ? NSColor.black : NSColor.white).withAlphaComponent(0.95)
            content.shadow = halo
        } else {
            content.shadow = nil
        }
        switch material {
        case .translucent:
            // Keep a light/dark base behind template icons even with an extreme custom tint.
            let tintedBase = base.blended(withFraction: strength * 0.38, of: tint) ?? base
            let opacity: CGFloat = reduced || contrast ? 1 : configuration.opacity
            surface?.layer?.backgroundColor = tintedBase.withAlphaComponent(opacity).cgColor
        case .frosted:
            tintWash.layer?.backgroundColor = tint.withAlphaComponent(strength * 0.32).cgColor
        case .quietGlass:
            (surface as? QuietShelfGlass)?.apply(configuration)
        case .liquid, .appleGlass:
            if #available(macOS 26, *) {
                let optics = surface as? ClearShelfGlass
                guard let glass = optics?.glass ?? surface as? NSGlassEffectView else { return }
                if let optics {
                    optics.frostAmount = CGFloat(configuration.frostAmount)
                    glass.appearance = opticalAppearance
                }
                glass.tintColor = strength == 0 ? nil : tint.withAlphaComponent(strength * 0.65)
                if #available(macOS 27, *) {
                    glass.effectIsInteractive = blendingMode == .behindWindow && !workspace.accessibilityDisplayShouldReduceMotion
                }
            }
        }
    }

    override func layout() {
        super.layout()
        updateCorners()
    }

    private func updateCorners() {
        let radius = ShelfMetrics.cornerRadius(for: bounds.size)
        if layer?.cornerRadius != radius { layer?.cornerRadius = radius }
        // The clear-glass containers also host the foreground. Only their
        // optical children need a second curve; the outer shelf clips the content.
        if activeMaterial?.usesGlassForeground == false, let materialLayer = surface?.layer, materialLayer.cornerRadius != radius {
            materialLayer.cornerCurve = .continuous
            materialLayer.cornerRadius = radius
            // WindowServer composites behind-window blur separately from the view's layer.
            (surface as? NSVisualEffectView)?.maskImage = Self.blurMask(radius: radius)
        }
        if #available(macOS 26, *) {
            let optics = surface as? ClearShelfGlass
            if let glass = optics?.glass ?? surface as? NSGlassEffectView, glass.cornerRadius != radius {
                glass.cornerRadius = radius
                optics?.needsLayout = true
            }
        }
    }

    private static func blurMask(radius: CGFloat) -> NSImage? {
        guard radius > 0 else { return nil }
        let side = radius * 2 + 1
        let mask = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let shape = CALayer()
            shape.frame = rect
            shape.cornerRadius = radius
            shape.cornerCurve = .continuous
            shape.backgroundColor = NSColor.white.cgColor
            shape.render(in: context)
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    private func install(_ material: ShelfMaterial) {
        let responder = window?.firstResponder as? NSView
        let restoreFocus = responder?.isDescendant(of: content) == true
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = true
        tintWash.removeFromSuperview()
        surface?.removeFromSuperview()

        let next: NSView
        switch material {
        case .liquid, .appleGlass:
            if #available(macOS 26, *) {
                if material == .appleGlass {
                    next = ClearShelfGlass(frame: bounds, content: content)
                } else {
                    let glass = NSGlassEffectView(frame: bounds)
                    glass.style = .regular
                    glass.contentView = NSView()
                    next = glass
                }
            } else { return }
        case .quietGlass:
            next = QuietShelfGlass(frame: bounds, configuration: configuration, content: content, blendingMode: blendingMode)
        case .frosted:
            let frost = NSVisualEffectView(frame: bounds)
            frost.material = .popover
            frost.blendingMode = blendingMode
            frost.state = .active
            tintWash.frame = frost.bounds
            tintWash.autoresizingMask = [.width, .height]
            frost.addSubview(tintWash)
            next = frost
        case .translucent:
            next = NSView(frame: bounds)
        }

        activeMaterial = material
        surface = next
        next.wantsLayer = true
        next.autoresizingMask = [.width, .height]
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(next)
        // The outer shelf clips the foreground once. Nesting it in an AppKit
        // material multiplies corner coverage at the edge, visibly tightening the curve.
        if !material.usesGlassForeground { addSubview(content) }
        if restoreFocus, let responder { window?.makeFirstResponder(responder) }
    }
}

/// Mix the native scattering pass into the center, retaining the strongest lensing at the bevel.
/// The foreground stays outside the optics so icons and keyboard focus remain sharp.
@available(macOS 26, *)
@MainActor final class ClearShelfGlass: NSView {
    private final class OpticalView: NSGlassEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    let glass: NSGlassEffectView = OpticalView()
    private let bezel = GlassBezel()
    var frostAmount: CGFloat = 0 {
        didSet { if frostAmount != oldValue { updateBezel() } }
    }

    private final class ReflectionView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    init(frame: NSRect, content: NSView) {
        super.init(frame: frame)
        glass.style = .clear
        glass.contentView = NSView()
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        glass.wantsLayer = true
        glass.layer?.mask = bezel.materialMask
        // Clear glass compresses the luminance range of the sampled scene. Recover
        // highlights and the shadow toe in the optical pass, before blending it over
        // the desktop. This curve does not process the shelf's icons or text.
        if let tone = CIFilter(name: "CIToneCurve") {
            let points: [CGPoint] = [.zero, CGPoint(x: 0.18, y: 0.11), CGPoint(x: 0.48, y: 0.48),
                                     CGPoint(x: 0.78, y: 0.97), CGPoint(x: 1, y: 1)]
            for (index, point) in points.enumerated() {
                tone.setValue(CIVector(cgPoint: point), forKey: "inputPoint" + String(index))
            }
            glass.contentFilters = [tone]
        }
        addSubview(glass)

        let reflection = ReflectionView(frame: bounds)
        reflection.autoresizingMask = [.width, .height]
        reflection.wantsLayer = true
        reflection.layer?.addSublayer(bezel.highlight)
        reflection.setAccessibilityElement(false)
        addSubview(reflection)

        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateBezel()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func updateBezel() {
        bezel.layout(in: bounds, cornerRadius: glass.cornerRadius, scale: window?.backingScaleFactor ?? 1,
                     centerAmount: 0.72 * frostAmount)
    }
}

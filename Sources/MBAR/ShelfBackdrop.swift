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
        let needsShadow = activeMaterial != .appleGlass
        if window.hasShadow != needsShadow { window.hasShadow = needsShadow }
    }

    @objc private func refreshMaterial() {
        let workspace = NSWorkspace.shared
        let reduced = workspace.accessibilityDisplayShouldReduceTransparency
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        var material: ShelfMaterial = reduced ? .translucent : configuration.material
        if #unavailable(macOS 26) {
            if material == .liquid || material == .appleGlass { material = .frosted }
        }
        let isGlass = material == .liquid || material == .appleGlass
        let radius: CGFloat
        switch configuration.material {
        case .appleGlass: radius = 16
        case .liquid: radius = 14
        default: radius = 10
        }
        if activeMaterial != material { install(material) }
        updateShelfWindowShadow()
        layer?.cornerRadius = radius
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base = NSColor(srgbRed: dark ? 0.13 : 0.97, green: dark ? 0.14 : 0.97,
                           blue: dark ? 0.16 : 0.98, alpha: 1)
        let tint = NSColor(srgbRed: configuration.tint.red, green: configuration.tint.green,
                           blue: configuration.tint.blue, alpha: 1)
        let strength = CGFloat(configuration.intensity)
        let border = dark ? NSColor.white : NSColor.black
        layer?.borderWidth = contrast ? 1 : (isGlass ? 0 : 0.5)
        layer?.borderColor = border.withAlphaComponent(contrast ? 0.6 : (dark ? 0.25 : 0.16)).cgColor

        let clearGlass = material == .appleGlass
        // Only an explicit color choice paints the interior. The icon halo
        // supplies local contrast across light and dark desktop regions.
        layer?.backgroundColor = clearGlass && strength > 0 ? tint.withAlphaComponent(strength * 0.30).cgColor : nil
        let needsHalo = material == .translucent && !reduced && !contrast && configuration.opacity < 0.62
        if clearGlass || needsHalo {
            // A narrow halo stays with the glyphs as the desktop behind a low-opacity panel changes.
            let halo = NSShadow()
            halo.shadowOffset = clearGlass ? NSSize(width: 0, height: -0.9) : .zero
            halo.shadowBlurRadius = clearGlass ? 0.6 : 1.5
            halo.shadowColor = (dark || clearGlass ? NSColor.black : NSColor.white).withAlphaComponent(0.95)
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
        case .liquid, .appleGlass:
            if #available(macOS 26, *) {
                let optics = surface as? ClearShelfGlass
                guard let glass = optics?.glass ?? surface as? NSGlassEffectView else { return }
                glass.cornerRadius = radius
                if let optics {
                    optics.frostAmount = CGFloat(configuration.frostAmount)
                    optics.appearance = NSAppearance(named: contrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
                }
                glass.tintColor = strength == 0 ? nil : tint.withAlphaComponent(strength * 0.65)
                if #available(macOS 27, *) {
                    glass.effectIsInteractive = blendingMode == .behindWindow && !workspace.accessibilityDisplayShouldReduceMotion
                }
            }
        }
    }

    private func install(_ material: ShelfMaterial) {
        let responder = window?.firstResponder as? NSView
        let restoreFocus = responder?.isDescendant(of: content) == true
        if #available(macOS 26, *), let glass = surface as? NSGlassEffectView {
            glass.contentView = nil
        }
        content.removeFromSuperview()
        // NSGlassEffectView switches its contentView to constraints. Once detached,
        // return the host to frame-based sizing before the next surface adopts it.
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
                    glass.contentView = content
                    next = glass
                }
            } else { return }
        case .frosted:
            let frost = NSVisualEffectView(frame: bounds)
            frost.material = .popover
            frost.blendingMode = blendingMode
            frost.state = .active
            tintWash.frame = frost.bounds
            tintWash.autoresizingMask = [.width, .height]
            frost.addSubview(tintWash)
            frost.addSubview(content)
            next = frost
        case .translucent:
            next = NSView(frame: bounds)
            next.wantsLayer = true
            next.addSubview(content)
        }

        activeMaterial = material
        surface = next
        next.autoresizingMask = [.width, .height]
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(next)
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

        // Two short, opposing shadows outline just the glyphs on white desktop
        // content. Keeping this one on a separate view leaves the glass clear.
        let foreground = NSView(frame: bounds)
        foreground.autoresizingMask = [.width, .height]
        let stroke = NSShadow()
        stroke.shadowOffset = NSSize(width: -0.5, height: 0.8)
        stroke.shadowColor = .black
        stroke.shadowBlurRadius = 0.65
        foreground.shadow = stroke
        foreground.addSubview(content)
        addSubview(foreground)
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

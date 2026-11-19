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

    @objc private func refreshMaterial() {
        let workspace = NSWorkspace.shared
        let reduced = workspace.accessibilityDisplayShouldReduceTransparency
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
        layer?.cornerRadius = radius
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base = NSColor(srgbRed: dark ? 0.13 : 0.97, green: dark ? 0.14 : 0.97,
                           blue: dark ? 0.16 : 0.98, alpha: 1)
        let tint = NSColor(srgbRed: configuration.tint.red, green: configuration.tint.green,
                           blue: configuration.tint.blue, alpha: 1)
        let strength = CGFloat(configuration.intensity)
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        let border = dark ? NSColor.white : NSColor.black
        layer?.borderWidth = contrast ? 1 : (isGlass ? 0 : 0.5)
        layer?.borderColor = border.withAlphaComponent(contrast ? 0.6 : (dark ? 0.25 : 0.16)).cgColor

        let clearGlass = material == .appleGlass
        // Clear glass leaves wallpaper luminosity intact. Dim only the area behind
        // this panel and use light semantic labels in the glass content hierarchy.
        layer?.backgroundColor = clearGlass ? NSColor.black.withAlphaComponent(contrast ? 0.45 : 0.30).cgColor : nil
        let needsHalo = material == .translucent && !reduced && !contrast && configuration.opacity < 0.62
        if clearGlass || needsHalo {
            // A narrow halo stays with the glyphs as the desktop behind a low-opacity panel changes.
            let halo = NSShadow()
            halo.shadowOffset = clearGlass ? NSSize(width: 0, height: -0.5) : .zero
            halo.shadowBlurRadius = clearGlass ? 2.5 : 1.5
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
        tintWash.removeFromSuperview()
        surface?.removeFromSuperview()

        let next: NSView
        switch material {
        case .liquid, .appleGlass:
            if #available(macOS 26, *) {
                if material == .appleGlass {
                    let optics = ClearShelfGlass(frame: bounds)
                    optics.addSubview(content)
                    next = optics
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

/// Keep the native optical rim at full strength. Window-server clear glass can
/// still average away fine desktop texture in a floating panel, so composite its
/// center at a lower strength. Icons are siblings of this masked optical layer,
/// retaining their own colors, hit targets and full opacity.
@available(macOS 26, *)
@MainActor final class ClearShelfGlass: NSView {
    private final class OpticalView: NSGlassEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    let glass: NSGlassEffectView = OpticalView()
    private let opticalMask = CALayer()
    private let rim = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass.style = .clear
        glass.contentView = NSView()
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        glass.wantsLayer = true
        opticalMask.backgroundColor = NSColor.white.withAlphaComponent(0.42).cgColor
        rim.fillColor = nil
        rim.strokeColor = NSColor.white.cgColor
        rim.lineWidth = 4
        opticalMask.addSublayer(rim)
        glass.layer?.mask = opticalMask
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        opticalMask.frame = glass.bounds
        rim.contentsScale = window?.backingScaleFactor ?? 1
        let inset = rim.lineWidth / 2
        let radius = max(0, glass.cornerRadius - inset)
        rim.path = CGPath(roundedRect: glass.bounds.insetBy(dx: inset, dy: inset),
                          cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
    }
}

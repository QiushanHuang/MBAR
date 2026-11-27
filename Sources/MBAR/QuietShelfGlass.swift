import AppKit
import MBARCore

/// AppKit chooses clear glass's optics from its window's activity. A non-key child
/// draws the original material while the shelf's own window receives input.
@MainActor final class QuietShelfGlass: NSView {
    private final class OpticalPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let panel: OpticalPanel
    private let original: ShelfBackdrop
    private let isPreview: Bool

    init(frame: NSRect, configuration: ShelfAppearance, content: NSView, blendingMode: NSVisualEffectView.BlendingMode) {
        isPreview = blendingMode == .withinWindow
        let local = NSRect(origin: .zero, size: frame.size)
        original = ShelfBackdrop(frame: local, configuration: Self.originalGlass(configuration),
                                 content: isPreview ? content : NSView(), blendingMode: blendingMode)
        panel = OpticalPanel(contentRect: local, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init(frame: frame)

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.isRestorable = false
        panel.setAccessibilityElement(false)

        let clip = NSView(frame: local)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(original)
        panel.contentView = clip
        // The editor's sample is decorative and sits over an opaque canvas. The
        // real shelf keeps all buttons and first responders in its input window.
        if !isPreview {
            // WindowServer passes clicks through fully transparent pixels. Just
            // over half an 8-bit alpha step keeps the entire button padding hittable.
            wantsLayer = true
            layer?.backgroundColor = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.55 / 255).cgColor
            addSubview(content)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func originalGlass(_ appearance: ShelfAppearance) -> ShelfAppearance {
        var reference = appearance
        reference.material = .appleGlass
        return reference
    }

    func apply(_ appearance: ShelfAppearance) {
        original.apply(Self.originalGlass(appearance))
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let owner = window, owner !== newWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didUpdateNotification, object: owner)
            detachPanel()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let owner = window else { return }
        if isPreview {
            // SwiftUI can move the preview's ancestors without resizing this view.
            NotificationCenter.default.addObserver(self, selector: #selector(alignPanel),
                                                   name: NSWindow.didUpdateNotification, object: owner)
        }
        alignPanel()
    }

    override func layout() {
        super.layout()
        alignPanel()
    }

    override func viewDidHide() {
        super.viewDidHide()
        detachPanel()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        alignPanel()
    }

    private func detachPanel() {
        guard let owner = panel.parent else { return }
        owner.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    @objc private func alignPanel() {
        let visible = isPreview ? bounds.intersection(visibleRect) : bounds
        guard let owner = window, !isHiddenOrHasHiddenAncestor, !visible.isEmpty else {
            detachPanel()
            return
        }
        let target = owner.convertToScreen(convert(visible, to: nil))
        if panel.frame != target { panel.setFrame(target, display: false) }
        let source = NSRect(origin: NSPoint(x: bounds.minX - visible.minX, y: bounds.minY - visible.minY), size: bounds.size)
        if original.frame != source { original.frame = source }
        guard panel.parent !== owner else { return }
        panel.appearanceSource = owner
        panel.colorSpace = owner.colorSpace
        panel.level = owner.level
        var behavior: NSWindow.CollectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        if owner.collectionBehavior.contains(.canJoinAllSpaces) { behavior.insert(.canJoinAllSpaces) }
        panel.collectionBehavior = behavior
        owner.addChildWindow(panel, ordered: isPreview ? .above : .below)
    }
}

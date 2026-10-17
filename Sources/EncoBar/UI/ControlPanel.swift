import AppKit
import SwiftUI
import EncoCore

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Arrowless system-material panel, always placed below the menu bar.
final class ControlPanel {
    static let size = NSSize(width: 300, height: 240)
    private let window: MenuPanel
    private var outsideClick: Any?
    private var escapeKey: Any?
    private let log: (String) -> Void
    var isShown: Bool { window.isVisible }

    init(model: EarbudModel) {
        log = { [weak model] in model?.record($0) }
        window = MenuPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "EncoBar"
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        // A nonactivating menu panel must not also be hidden by AppKit's
        // application activation cycle. Explicit click/Escape dismissal owns it.
        window.hidesOnDeactivate = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let bounds = NSRect(origin: .zero, size: Self.size)
        let hosting = NSHostingView(rootView: PopoverView(model: model))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = 16
            glass.contentView = hosting
            glass.autoresizingMask = [.width, .height]
            // Bound the complete composited glass surface, not just SwiftUI
            // content. Glass as a window root can leave a faint square fringe.
            let surface = Self.roundedSurface(bounds: bounds)
            surface.addSubview(glass)
            window.contentView = surface
        } else {
            window.contentView = Self.legacyMaterial(containing: hosting, bounds: bounds)
        }
    }

    private static func roundedSurface(bounds: NSRect) -> NSView {
        let surface = NSView(frame: bounds)
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.clear.cgColor
        surface.layer?.isOpaque = false
        surface.layer?.cornerRadius = 16
        surface.layer?.cornerCurve = .circular
        surface.layer?.masksToBounds = true
        return surface
    }

    private static func legacyMaterial(containing hosting: NSView, bounds: NSRect) -> NSView {
        let container = roundedSurface(bounds: bounds)
        let material = NSVisualEffectView(frame: container.bounds)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        // Mask the effect itself: layer clipping alone can leave blur corners
        // outside the rounded content on some macOS compositing paths.
        let mask = NSImage(size: Self.size)
        mask.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: Self.size), xRadius: 16, yRadius: 16).fill()
        mask.unlockFocus()
        material.maskImage = mask
        container.addSubview(material)
        container.addSubview(hosting)
        return container
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let statusWindow = button.window, let screen = statusWindow.screen ?? NSScreen.main else { return }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = PanelPlacement.frame(anchor: anchor, visible: screen.visibleFrame, size: Self.size)
        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        window.invalidateShadow()
        removeMonitors()
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self,
                  PanelPlacement.shouldDismissClick(at: NSEvent.mouseLocation, panel: self.window.frame, anchor: anchor) else { return }
            self.hide()
        }
        escapeKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
        log("面板已显示；窗口可见：\(window.isVisible)")
    }

    func hide() { window.orderOut(nil); removeMonitors() }
    private func removeMonitors() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick); self.outsideClick = nil }
        if let escapeKey { NSEvent.removeMonitor(escapeKey); self.escapeKey = nil }
    }
    deinit { removeMonitors() }
}

//
//  NotchWindow.swift
//  ClaudeIsland
//
//  Transparent always-on-top panel that hosts the notch UI. Hover detection
//  is handled by polling NSEvent.mouseLocation (see EventMonitors) — we no
//  longer install global event monitors or post synthetic clicks, so no
//  Accessibility permission is needed.
//

import AppKit

// Use NSPanel subclass for non-activating behavior
class NotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Floating panel behavior
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        // Transparent configuration
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false

        // CRITICAL: Prevent window from moving during space switches
        isMovable = false

        // Window behavior - stays on all spaces, above menu bar
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        // Above the menu bar
        level = .mainMenu + 3

        // Enable tooltips even when app is inactive (needed for panel windows)
        allowsToolTipsWhenApplicationIsInactive = true

        // Start ignoring mouse events; NotchWindowController flips this to
        // false whenever the panel is open so buttons inside receive clicks.
        ignoresMouseEvents = true

        isReleasedWhenClosed = true
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Click forwarding (Accessibility-gated)

    /// When the user has opted into Accessibility, intercept clicks that
    /// land inside our window bounds but outside any hit-testable view
    /// (i.e. the transparent area around the panel) and re-post them at
    /// the same screen point. The window briefly becomes click-through
    /// so the synthetic event reaches the real target window. Net effect:
    /// one click both dismisses our panel AND interacts with the app
    /// behind it. Without AX this method is a no-op and the click only
    /// dismisses our panel — user then has to click again.
    override func sendEvent(_ event: NSEvent) {
        if AccessibilityHelper.isTrusted,
           event.type == .leftMouseDown || event.type == .leftMouseUp ||
           event.type == .rightMouseDown || event.type == .rightMouseUp,
           let contentView = self.contentView,
           contentView.hitTest(event.locationInWindow) == nil {
            let screenLocation = convertPoint(toScreen: event.locationInWindow)
            ignoresMouseEvents = true
            DispatchQueue.main.async { [weak self] in
                self?.repostMouseEvent(event, at: screenLocation)
            }
            return
        }
        super.sendEvent(event)
    }

    private func repostMouseEvent(_ event: NSEvent, at screenLocation: NSPoint) {
        guard let screen = NSScreen.main else { return }
        let cgPoint = CGPoint(x: screenLocation.x, y: screen.frame.height - screenLocation.y)
        let mouseType: CGEventType
        switch event.type {
        case .leftMouseDown:  mouseType = .leftMouseDown
        case .leftMouseUp:    mouseType = .leftMouseUp
        case .rightMouseDown: mouseType = .rightMouseDown
        case .rightMouseUp:   mouseType = .rightMouseUp
        default: return
        }
        let button: CGMouseButton =
            (event.type == .rightMouseDown || event.type == .rightMouseUp) ? .right : .left
        CGEvent(
            mouseEventSource: nil,
            mouseType: mouseType,
            mouseCursorPosition: cgPoint,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
    }
}

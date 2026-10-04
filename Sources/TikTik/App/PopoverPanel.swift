import AppKit
import SwiftUI

/// The popover: a borderless, non-activating panel hosting SwiftUI.
///
/// Non-activating matters: opening it does not make TikTik the frontmost app,
/// so tracking (and the Now tab) keep seeing the app you were actually using.
@MainActor
final class PopoverPanel: NSPanel {
    static let contentSize = NSSize(width: 380, height: 560)
    /// Gap between the menu bar and the top of the panel.
    private static let menuBarGap: CGFloat = 6
    /// Minimum distance from the screen edges.
    private static let screenMargin: CGFloat = 8

    var onDismiss: (() -> Void)?

    private var outsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var spaceChangeObserver: NSObjectProtocol?

    // A convenience init keeps NSWindow's designated initializers (including init?(coder:)) inherited.
    convenience init<Content: View>(rootView: Content) {
        self.init(
            contentRect: NSRect(origin: .zero, size: PopoverPanel.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let size = PopoverPanel.contentSize
        let hosting = NSHostingView(rootView: rootView.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        contentView = hosting
    }

    // Borderless panels refuse key status by default; we want it for keyboard input (Esc, menus).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Shows the panel centred under `anchor` (the status item's frame in screen coordinates),
    /// kept fully on the screen that contains it.
    func show(below anchor: NSRect) {
        let size = Self.contentSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)

        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        let y = anchor.minY - size.height - Self.menuBarGap

        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        orderFrontRegardless()
        makeKey()
        invalidateShadow()
        installMonitors()
    }

    func dismiss() {
        guard isVisible else { return }
        removeMonitors()
        orderOut(nil)
        onDismiss?()
    }

    // MARK: - Dismissal triggers

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps (global monitors only see events outside TikTik).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        // Esc closes the panel.
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.isKeyWindow else { return event }
            self.dismiss()
            return nil
        }
        // Switching Spaces closes it too.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func removeMonitors() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = escapeKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = spaceChangeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        outsideClickMonitor = nil
        escapeKeyMonitor = nil
        spaceChangeObserver = nil
    }
}

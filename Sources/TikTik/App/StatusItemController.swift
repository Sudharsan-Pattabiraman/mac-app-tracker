import AppKit
import SwiftUI

/// Owns the menu bar item and the popover panel, and toggles the panel on click.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: PopoverPanel

    /// Called just before the panel appears (resets to the default tab).
    var onOpen: (() -> Void)?
    /// Called after the panel closes.
    var onClose: (() -> Void)?

    var isPanelVisible: Bool { panel.isVisible }

    init(panel: PopoverPanel) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = panel
        super.init()

        panel.onDismiss = { [weak self] in
            self?.statusItem.button?.highlight(false)
            self?.onClose?()
        }

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "TikTik")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("TikTik")
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Renders a SwiftUI view into the status item as a template image (macOS tints it for the menu bar).
    func setLabel<Label: View>(_ label: Label) {
        guard let button = statusItem.button else { return }
        let renderer = ImageRenderer(content: label.frame(height: 18))
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        image.isTemplate = true
        button.image = image
    }

    func showPanel() {
        guard !panel.isVisible, let button = statusItem.button, let buttonWindow = button.window else { return }
        onOpen?()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: anchor)
        button.highlight(true)
    }

    /// Runs a modal dialog (save panel, alert, open panel) with the popover lowered beneath it.
    /// The popover floats at status-bar level, which would otherwise cover the dialog.
    func runModal(_ body: () -> Void) {
        let level = panel.level
        panel.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        body()
        panel.level = level
        if panel.isVisible { panel.makeKey() }
    }

    @objc private func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            panel.dismiss()
        } else {
            showPanel()
        }
    }
}

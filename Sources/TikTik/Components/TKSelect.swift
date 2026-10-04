import AppKit
import SwiftUI

/// shadcn Select trigger that opens a native menu (SwiftUI's Menu ignores custom label styling on macOS).
struct TKSelect<Value: Hashable>: View {
    @Environment(\.palette) private var palette

    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    /// Optional glyph shown before the value (e.g. the menu bar style preview).
    var leading: AnyView? = nil

    var body: some View {
        Button {
            NativeMenu.show(
                items: options.map { option in
                    NativeMenu.Item(title: title(option), isChecked: option == selection) { selection = option }
                }
            )
        } label: {
            HStack(spacing: Space.s2) {
                if let leading { leading }
                Text(title(selection))
                    .font(TextStyle.bodySm.font)
                    .foregroundStyle(palette.foreground)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.mutedForeground)
            }
            .padding(.leading, Space.s2_5)
            .padding(.trailing, Space.s2)
            .frame(height: Size.selectHeight)
            .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.border, lineWidth: Size.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// Pops up an NSMenu at the mouse location and runs the chosen item's action.
@MainActor
enum NativeMenu {
    struct Item {
        let title: String
        var isChecked = false
        var isEnabled = true
        let action: () -> Void
    }

    static func show(items: [Item]) {
        let target = MenuTarget(actions: items.map(\.action))
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.font = NSFont(name: Fonts.regular, size: 12) ?? .menuFont(ofSize: 12)
        for (index, item) in items.enumerated() {
            let menuItem = NSMenuItem(title: item.title, action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
            menuItem.target = target
            menuItem.tag = index
            menuItem.state = item.isChecked ? .on : .off
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }
        // popUp blocks until the menu closes, so `target` stays alive for the whole interaction.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        withExtendedLifetime(target) {}
    }

    private final class MenuTarget: NSObject {
        let actions: [() -> Void]

        init(actions: [() -> Void]) {
            self.actions = actions
        }

        @objc func fire(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag]()
        }
    }
}

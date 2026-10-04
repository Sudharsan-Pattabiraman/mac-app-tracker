import AppKit
import SwiftUI

/// `--sample-data` only: a small window to jump between the approved design states.
struct DesignReviewView: View {
    @Environment(AppState.self) private var state
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.palette) private var palette

    let provider: SampleUsageProvider
    let openPopover: () -> Void
    let showWelcome: () -> Void

    @State private var scenario: SampleScenario = .normal

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Design review").textStyle(.display)
                Text("Sample data only. Compare with design/tiktik-design.html.").textStyle(.label)
            }

            group("Data scenario") {
                ForEach(SampleScenario.allCases) { item in
                    choice(item.title, selected: scenario == item) {
                        scenario = item
                        provider.scenario = item
                        state.reload()
                    }
                }
            }

            group("Paused") {
                choice("Not paused", selected: state.pause == nil) { state.pause = nil }
                choice("Paused for 45 min", selected: state.pause?.endDate != nil) {
                    state.pause = .until(Date().addingTimeInterval(45 * 60))
                }
                choice("Paused until resumed", selected: state.pause == .indefinitely) { state.pause = .indefinitely }
            }

            group("Menu bar style") {
                ForEach(MenuBarStyle.allCases) { style in
                    choice("\(style.letter) · \(style.title)", selected: preferences.menuBarStyle == style) {
                        preferences.menuBarStyle = style
                    }
                }
            }

            HStack(spacing: Space.s2) {
                Button("Open popover", action: openPopover).buttonStyle(.tk(.primary, size: .small))
                Button("Show welcome window", action: showWelcome).buttonStyle(.tk(.outline, size: .small))
            }
        }
        .padding(Space.s5)
        .frame(width: 300, alignment: .leading)
        .foregroundStyle(palette.foreground)
        .background(palette.background)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).textStyle(.caption)
            content()
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                Circle()
                    .strokeBorder(palette.border, lineWidth: Size.border)
                    .background(Circle().fill(selected ? palette.primary : .clear).padding(3))
                    .frame(width: 12, height: 12)
                Text(title).textStyle(.bodySm)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Hosts the design review window.
@MainActor
final class DesignReviewWindowController {
    private var window: NSWindow?

    func show<Content: View>(_ content: Content) {
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "TikTik · Design review"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: screen.minX + 40, y: screen.maxY - window.frame.height - 40))
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

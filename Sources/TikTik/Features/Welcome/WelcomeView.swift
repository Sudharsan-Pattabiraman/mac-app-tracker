import AppKit
import SwiftUI

/// First-launch window (SPEC 5.8): menu bar style, Chrome access, launch at login.
struct WelcomeView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.palette) private var palette
    let onContinue: () -> Void

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4 + 2) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Welcome to TikTik").textStyle(.display)
                Text("Tracks active, idle and away time on this Mac, per app. Everything stays on this Mac.")
                    .textStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Menu bar style · change any time in Settings").textStyle(.label)
                LazyVGrid(columns: columns, spacing: Space.s2) {
                    ForEach(MenuBarStyle.allCases) { style in
                        StyleTile(style: style, isSelected: preferences.menuBarStyle == style,
                                  dailyGoal: TimeInterval(preferences.dailyGoalHours * 3600)) {
                            preferences.menuBarStyle = style
                        }
                    }
                }
            }

            TKCard(padding: CardPadding.none) {
                VStack(spacing: 0) {
                    SettingRow("Website tracking in Chrome",
                               "macOS will ask once to let TikTik read the active tab's address in Chrome, Brave or Edge. Only the domain is stored. Incognito is never recorded.") {
                        Button("Allow…") {}
                            .buttonStyle(.tk(.outline, size: .small))
                            .help("Asks for access in milestone M5")
                    }
                    TKSeparator()
                    SettingRow("Launch at login", "Recommended. TikTik can't record time while it isn't running.") {
                        Toggle("", isOn: $preferences.launchAtLogin).toggleStyle(.tk).labelsHidden()
                    }
                }
            }

            HStack {
                Spacer()
                Button("Continue", action: onContinue).buttonStyle(.tk(.primary))
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s6 + Space.s2)
        .padding(.bottom, Space.s5)
        .frame(width: 520)
        .foregroundStyle(palette.foreground)
        .background(palette.background)
    }
}

private struct StyleTile: View {
    @Environment(\.palette) private var palette
    let style: MenuBarStyle
    let isSelected: Bool
    let dailyGoal: TimeInterval
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        Button(action: action) {
            VStack(spacing: Space.s2) {
                MenuBarLabel(style: style, activeToday: 342 * 60, dailyGoal: dailyGoal, isIdle: false,
                             pause: nil, tint: palette.foreground)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(palette.muted, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                HStack {
                    Text(style.title)
                    Spacer()
                    Text(style.letter).foregroundStyle(palette.mutedForeground)
                }
                .font(TextStyle.label.font)
            }
            .padding(Space.s2_5)
            .background(palette.background, in: shape)
            .overlay(shape.strokeBorder(isSelected ? palette.primary : palette.border,
                                        lineWidth: isSelected ? 2 : Size.border))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Hosts the welcome view in a small titled window.
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?

    func show<Content: View>(_ content: Content) {
        if window == nil {
            let hosting = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}

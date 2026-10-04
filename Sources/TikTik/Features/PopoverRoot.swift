import AppKit
import SwiftUI
import TikTikCore

/// The popover: header, tabs, content and footer (SPEC 5.3), plus detail and settings pages.
struct PopoverRoot: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            switch state.route {
            case .home:
                home
            case .detail(let app):
                AppDetailView(app: app)
            case .settings:
                SettingsView()
            }
        }
        .padding(Space.s3_5)
        .frame(width: Size.popover.width, height: Size.popover.height, alignment: .top)
        .foregroundStyle(palette.foreground)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.border, lineWidth: Size.border))
    }

    private var home: some View {
        @Bindable var state = state
        return VStack(spacing: Space.s3) {
            PopoverHeader(badge: badgeText)
            TKTabs(items: TimeTab.allCases, selection: $state.selectedTab, title: \.label, isLive: { $0 == .now })
            if let pause = state.pause {
                PauseBanner(pause: pause) { state.pause = nil }
            }
            Group {
                if state.selectedTab == .now {
                    NowView()
                } else {
                    RangeView(tab: state.selectedTab)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            PopoverFooter()
        }
    }

    private var badgeText: String {
        let tab = state.selectedTab
        let now = Date()
        switch tab {
        case .now:
            return "Now · " + Self.timeFormatter.string(from: now)
        case .h6, .h12, .h24:
            return "Last \(tab.label)"
        default:
            guard let window = tab.window(endingAt: now) else { return tab.label }
            return Self.dayFormatter.string(from: window.start) + " – " + Self.dayFormatter.string(from: now)
        }
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

/// Hourglass + "TikTik" on the left, range badge on the right.
struct PopoverHeader: View {
    let badge: String

    var body: some View {
        HStack(spacing: Space.s1_5) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .semibold))
            Text("TikTik").textStyle(.title)
            Spacer()
            TKBadge(text: badge)
        }
    }
}

/// "Tracking paused" banner with Resume (SPEC 5.3).
struct PauseBanner: View {
    let pause: PauseState
    let onResume: () -> Void

    var body: some View {
        TKBanner(systemImage: "pause.fill", title: "Tracking paused", subtitle: subtitle) {
            Button("Resume", action: onResume).buttonStyle(.tk(.outline, size: .small))
        }
    }

    private var subtitle: String {
        guard let end = pause.endDate else { return "Until you resume" }
        let left = DurationFormat.short(max(0, end.timeIntervalSinceNow))
        return "Resumes at \(PopoverRoot.timeFormatter.string(from: end)) · \(left) left"
    }
}

/// Pause/resume, settings and quit icon buttons, right-aligned (SPEC 5.3).
struct PopoverFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: Space.s1) {
            Spacer()
            if state.pause == nil {
                Button {
                    NativeMenu.show(items: [
                        .init(title: "Pause for 15 minutes") { state.pause = .until(Date().addingTimeInterval(15 * 60)) },
                        .init(title: "Pause for 1 hour") { state.pause = .until(Date().addingTimeInterval(3600)) },
                        .init(title: "Pause until I resume") { state.pause = .indefinitely },
                    ])
                } label: {
                    Image(systemName: "pause.fill").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.tk(.outline, size: .icon))
                .help("Pause tracking")
            } else {
                Button {
                    state.pause = nil
                } label: {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.tk(.outline, size: .icon))
                .help("Resume tracking")
            }
            Button {
                state.route = .settings
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.tk(.outline, size: .icon))
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.tk(.outline, size: .icon))
            .help("Quit TikTik")
        }
    }
}

/// "‹ Back" used by detail and settings pages.
struct BackButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { state.route = .home }
        } label: {
            HStack(spacing: Space.s1) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text("Back").font(TextStyle.control.font)
            }
        }
        .buttonStyle(.plain)
    }
}

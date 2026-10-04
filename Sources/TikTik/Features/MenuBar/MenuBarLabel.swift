import SwiftUI
import TikTikCore

/// What the menu bar item shows (SPEC 5.7). Rendered to a template image for the status item,
/// and used directly as a live preview on the welcome screen.
struct MenuBarLabel: View {
    let style: MenuBarStyle
    let activeToday: TimeInterval
    let dailyGoal: TimeInterval
    let isIdle: Bool
    let pause: PauseState?
    var now: Date = Date()
    /// Black for the template image (macOS tints it); the theme foreground for previews.
    var tint: Color = .black

    var body: some View {
        HStack(spacing: 4) {
            if let pause {
                pauseGlyph
                Text(pauseText(pause))
            } else {
                switch style {
                case .iconTime:
                    hourglass
                    timeText
                case .icon:
                    hourglass
                case .text:
                    timeText
                case .ring:
                    ring
                case .ringTime:
                    ring
                    timeText
                case .timeDot:
                    timeText
                    Circle().frame(width: 6, height: 6).opacity(isIdle ? 0.35 : 1)
                }
            }
        }
        .font(.custom(Fonts.regular, size: 12))
        .foregroundStyle(tint)
        .fixedSize()
    }

    private var hourglass: some View {
        Image(systemName: "hourglass").font(.system(size: 13, weight: .regular))
    }

    private var pauseGlyph: some View {
        Image(systemName: "pause.fill").font(.system(size: 10, weight: .bold))
    }

    private var timeText: some View {
        Text(DurationFormat.short(activeToday))
    }

    private var ring: some View {
        let progress = dailyGoal > 0 ? min(activeToday / dailyGoal, 1) : 0
        return ZStack {
            Circle().stroke(lineWidth: 2).opacity(0.3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
    }

    private func pauseText(_ pause: PauseState) -> String {
        guard let end = pause.endDate else { return "paused" }
        return DurationFormat.short(max(60, end.timeIntervalSince(now)))
    }
}

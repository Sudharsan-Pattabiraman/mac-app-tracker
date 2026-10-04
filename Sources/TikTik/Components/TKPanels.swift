import SwiftUI

/// Dashed banner for a temporary state (used for "Tracking paused").
struct TKBanner<Trailing: View>: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        HStack(spacing: Space.s2_5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Size.iconButton, height: Size.iconButton)
                .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: Size.border))
            VStack(alignment: .leading, spacing: Space.s0_5) {
                Text(title).textStyle(.bodySm)
                Text(subtitle).textStyle(.label)
            }
            Spacer(minLength: Space.s2)
            trailing()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2_5)
        .background(palette.muted, in: shape)
        .overlay(shape.strokeBorder(palette.border, style: StrokeStyle(lineWidth: Size.border, dash: [4, 3])))
    }
}

/// Centered empty state inside a card that fills the available space.
struct TKEmptyState: View {
    @Environment(\.palette) private var palette
    let systemImage: String?
    let title: String
    let message: String

    var body: some View {
        TKCard(padding: EdgeInsets(top: Space.s6, leading: Space.s6, bottom: Space.s6, trailing: Space.s6)) {
            VStack(spacing: Space.s2) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 16))
                    } else {
                        Text("—").textStyle(.body)
                    }
                }
                .foregroundStyle(palette.mutedForeground)
                .frame(width: 40, height: 40)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.border, style: StrokeStyle(lineWidth: Size.border, dash: [4, 3])))
                .padding(.bottom, Space.s1)
                Text(title).textStyle(.bodyStrong)
                Text(message)
                    .textStyle(.label)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Donut of Active / Idle / Away with the Active share in the centre.
struct TKRing: View {
    @Environment(\.palette) private var palette
    let active: TimeInterval
    let idle: TimeInterval
    let away: TimeInterval
    var diameter: CGFloat = 84
    var lineWidth: CGFloat = 10

    var body: some View {
        let total = max(active + idle + away, 1)
        let segments: [(Double, Color)] = [
            (active / total, palette.stateActive),
            (idle / total, palette.stateIdle),
            (away / total, palette.stateAway),
        ]
        let radius = (diameter - lineWidth) / 2
        let gap = 2 / (2 * .pi * radius)   // 2 pt gap between segments
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let start = segments[..<index].reduce(0) { $0 + $1.0 }
                let end = start + segment.0
                if segment.0 > gap {
                    Circle()
                        .trim(from: start, to: end - gap)
                        .stroke(segment.1, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .padding(lineWidth / 2)
                }
            }
            Text("\(Int((active / total * 100).rounded()))%")
                .font(.custom(Fonts.semibold, size: 12))
                .foregroundStyle(palette.foreground)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel("Active \(Int((active / total * 100).rounded())) percent")
    }
}

/// Legend row: colored square, name, value.
struct TKLegendItem: View {
    @Environment(\.palette) private var palette
    let tone: StateTone
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: 2).fill(palette.color(for: tone)).frame(width: 8, height: 8)
            Text(title)
            Spacer(minLength: Space.s2)
            Text(value).foregroundStyle(palette.foreground)
        }
        .font(TextStyle.bodySm.font)
    }
}

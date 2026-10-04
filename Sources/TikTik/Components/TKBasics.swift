import SwiftUI

/// shadcn Badge.
struct TKBadge: View {
    enum Variant { case primary, secondary, outline, destructive }

    @Environment(\.palette) private var palette
    let text: String
    var variant: Variant = .outline
    /// Optional status dot before the text.
    var dot: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        HStack(spacing: Space.s1_5) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.custom(Fonts.medium, size: TextStyle.label.size))
        .lineLimit(1)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s0_5)
        .foregroundStyle(foreground)
        .background(background, in: shape)
        .overlay(shape.strokeBorder(borderColor, lineWidth: Size.border))
        .fixedSize()
    }

    private var foreground: Color {
        switch variant {
        case .primary: return palette.primaryForeground
        case .destructive: return palette.destructive
        default: return palette.foreground
        }
    }

    private var background: Color {
        switch variant {
        case .primary: return palette.primary
        case .secondary: return palette.secondary
        case .outline, .destructive: return .clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .outline: return palette.border
        case .destructive: return palette.destructive
        default: return .clear
        }
    }
}

/// shadcn Progress: primary bar on an 18% primary track.
struct TKProgress: View {
    @Environment(\.palette) private var palette
    /// 0…1
    let value: Double
    var thin = false

    var body: some View {
        let height = thin ? Size.progressThin : Size.progress
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(palette.primary)
                    .frame(width: max(value > 0 ? height : 0, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// shadcn Separator.
struct TKSeparator: View {
    @Environment(\.palette) private var palette
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(palette.border)
            .frame(width: vertical ? Size.border : nil, height: vertical ? nil : Size.border)
    }
}

/// shadcn Switch as a ToggleStyle: `Toggle("", isOn: $x).toggleStyle(.tk)`.
struct TKSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        TKSwitchBody(configuration: configuration)
    }
}

extension ToggleStyle where Self == TKSwitchStyle {
    static var tk: TKSwitchStyle { TKSwitchStyle() }
}

private struct TKSwitchBody: View {
    @Environment(\.palette) private var palette
    let configuration: ToggleStyleConfiguration

    var body: some View {
        let isOn = configuration.isOn
        Capsule()
            .fill(isOn ? palette.primary : palette.border)
            .frame(width: Size.switchSize.width, height: Size.switchSize.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(palette.background)
                    .frame(width: Size.switchSize.height - 4, height: Size.switchSize.height - 4)
                    .shadow(color: palette.shadow, radius: 1, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .animation(.easeOut(duration: 0.15), value: isOn)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A small tooltip bubble (used by charts; positioned by the caller).
struct TKTooltipBubble: View {
    @Environment(\.palette) private var palette
    let text: String

    var body: some View {
        Text(text)
            .font(TextStyle.label.font)
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s1)
            .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.border, lineWidth: Size.border))
            .shadow(color: palette.shadow, radius: 4, y: 2)
            .fixedSize()
    }
}

/// Hover tooltip for any view: shows a bubble above it after a short delay.
struct TKTooltipModifier: ViewModifier {
    let text: String
    @State private var isShown = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if !Task.isCancelled { isShown = true }
                    }
                } else {
                    isShown = false
                }
            }
            .overlay(alignment: .top) {
                if isShown {
                    TKTooltipBubble(text: text)
                        .offset(y: -28)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isShown)
    }
}

extension View {
    func tkTooltip(_ text: String) -> some View {
        modifier(TKTooltipModifier(text: text))
    }
}

import SwiftUI

// TikTik design tokens (SPEC 5.1, design/design-system.html).
// Components use only these values: no literal colors, sizes or fonts elsewhere.

// MARK: - Color

struct Palette {
    let background: Color
    let foreground: Color
    let card: Color
    let primary: Color
    let primaryForeground: Color
    let secondary: Color
    let muted: Color
    let mutedForeground: Color
    let accent: Color
    let border: Color
    let destructive: Color
    let destructiveForeground: Color
    let ring: Color
    let stateActive: Color
    let stateIdle: Color
    let stateAway: Color
    /// Shadow tint for the selected tab pill, tooltips and menus.
    let shadow: Color

    /// Progress and chart tracks: primary at 18%.
    var track: Color { primary.opacity(0.18) }

    func color(for state: StateTone) -> Color {
        switch state {
        case .active: return stateActive
        case .idle: return stateIdle
        case .away: return stateAway
        }
    }

    static let light = Palette(
        background: Color(hex: 0xFFFFFF),
        foreground: Color(hex: 0x09090B),
        card: Color(hex: 0xFFFFFF),
        primary: Color(hex: 0x18181B),
        primaryForeground: Color(hex: 0xFAFAFA),
        secondary: Color(hex: 0xF4F4F5),
        muted: Color(hex: 0xF4F4F5),
        mutedForeground: Color(hex: 0x71717B),
        accent: Color(hex: 0xF4F4F5),
        border: Color(hex: 0xE4E4E7),
        destructive: Color(hex: 0xE7000B),
        destructiveForeground: Color(hex: 0xFAFAFA),
        ring: Color(hex: 0x9F9FA9),
        stateActive: Color(hex: 0x18181B),
        stateIdle: Color(hex: 0x8D8D8F),
        stateAway: Color(hex: 0xDADADB),
        shadow: Color.black.opacity(0.08)
    )

    static let dark = Palette(
        background: Color(hex: 0x09090B),
        foreground: Color(hex: 0xFAFAFA),
        card: Color(hex: 0x18181B),
        primary: Color(hex: 0xE4E4E7),
        primaryForeground: Color(hex: 0x18181B),
        secondary: Color(hex: 0x27272A),
        muted: Color(hex: 0x27272A),
        mutedForeground: Color(hex: 0x9F9FA9),
        accent: Color(hex: 0x27272A),
        border: Color.white.opacity(0.10),
        destructive: Color(hex: 0xFF6467),
        destructiveForeground: Color(hex: 0xFAFAFA),
        ring: Color(hex: 0x71717B),
        stateActive: Color(hex: 0xE4E4E7),
        stateIdle: Color(hex: 0x606063),
        stateAway: Color(hex: 0x38383B),
        shadow: Color.black.opacity(0.4)
    )
}

/// The three tracked states as colors (kept separate from TikTikCore so Core stays UI-free).
enum StateTone {
    case active, idle, away
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Resolves the palette from the current light/dark appearance.
private struct ThemeRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    var body: some View {
        content.environment(\.palette, colorScheme == .dark ? .dark : .light)
    }
}

extension View {
    /// Apply once at the root of every window or panel.
    func themed() -> some View {
        ThemeRoot(content: self)
    }
}

extension Color {
    /// 0xRRGGBB in sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Spacing (4 pt scale)

enum Space {
    static let s0_5: CGFloat = 2
    static let s1: CGFloat = 4
    static let s1_5: CGFloat = 6
    static let s2: CGFloat = 8
    static let s2_5: CGFloat = 10
    static let s3: CGFloat = 12
    static let s3_5: CGFloat = 14
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
}

// MARK: - Radius (--radius = 10)

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14
}

// MARK: - Sizes

enum Size {
    static let popover = CGSize(width: 380, height: 560)
    static let buttonHeight: CGFloat = 30
    static let buttonHeightSmall: CGFloat = 26
    static let iconButton: CGFloat = 26
    static let selectHeight: CGFloat = 28
    static let switchSize = CGSize(width: 32, height: 18)
    static let appIcon: CGFloat = 20
    static let appIconLarge: CGFloat = 32
    static let appIconHero: CGFloat = 40
    static let progress: CGFloat = 6
    static let progressThin: CGFloat = 4
    static let border: CGFloat = 1
    static let focusRing: CGFloat = 2
}

// MARK: - Typography (JetBrains Mono)

enum TextStyle {
    case caption, label, bodySm, body, bodyStrong, title, heading, display, hero
    /// Tab, button and select labels.
    case control
    /// Chart axis ticks.
    case axis

    var size: CGFloat {
        switch self {
        case .axis: return 9
        case .caption: return 10
        case .label: return 11
        case .bodySm, .control: return 12
        case .body, .bodyStrong: return 13
        case .title: return 14
        case .heading: return 15
        case .display: return 17
        case .hero: return 30
        }
    }

    var fontName: String {
        switch self {
        case .label, .bodySm, .body, .axis: return Fonts.regular
        case .caption, .bodyStrong, .control: return Fonts.medium
        case .title, .heading, .display, .hero: return Fonts.semibold
        }
    }

    /// Letter spacing in points (the em values from the design system × size).
    var tracking: CGFloat {
        switch self {
        case .caption: return 0.05 * size
        case .display: return -0.01 * size
        case .hero: return -0.02 * size
        default: return 0
        }
    }

    var isUppercase: Bool { self == .caption }
    var isMuted: Bool { self == .label || self == .caption || self == .axis }

    var font: Font { .custom(fontName, size: size) }
}

private struct TextStyleModifier: ViewModifier {
    @Environment(\.palette) private var palette
    let style: TextStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        let styled = content
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
        if style.isMuted {
            styled.foregroundStyle(palette.mutedForeground)
        } else {
            styled
        }
    }
}

extension View {
    func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}

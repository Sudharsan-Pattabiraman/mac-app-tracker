import SwiftUI

/// shadcn Button as a ButtonStyle: `.buttonStyle(.tk(.outline, size: .icon))`.
struct TKButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, outline, ghost, destructive }
    enum ButtonSize { case regular, small, icon }

    var variant: Variant = .primary
    var size: ButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        TKButtonBody(configuration: configuration, variant: variant, size: size)
    }
}

extension ButtonStyle where Self == TKButtonStyle {
    static func tk(_ variant: TKButtonStyle.Variant = .primary,
                   size: TKButtonStyle.ButtonSize = .regular) -> TKButtonStyle {
        TKButtonStyle(variant: variant, size: size)
    }
}

private struct TKButtonBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let configuration: ButtonStyleConfiguration
    let variant: TKButtonStyle.Variant
    let size: TKButtonStyle.ButtonSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        configuration.label
            .font(TextStyle.control.font)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(width: size == .icon ? Size.iconButton : nil, height: height)
            .foregroundStyle(foreground)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(variant == .outline ? palette.border : .clear, lineWidth: Size.border))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var height: CGFloat {
        switch size {
        case .regular: return Size.buttonHeight
        case .small: return Size.buttonHeightSmall
        case .icon: return Size.iconButton
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular: return Space.s3
        case .small: return Space.s2_5
        case .icon: return 0
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: return palette.primaryForeground
        case .destructive: return palette.destructiveForeground
        default: return palette.foreground
        }
    }

    private var background: Color {
        let hover = isHovering && isEnabled
        switch variant {
        case .primary: return hover ? palette.primary.opacity(0.9) : palette.primary
        case .secondary: return hover ? palette.secondary.opacity(0.8) : palette.secondary
        case .outline: return hover ? palette.accent : palette.background
        case .ghost: return hover ? palette.accent : .clear
        case .destructive: return hover ? palette.destructive.opacity(0.9) : palette.destructive
        }
    }
}

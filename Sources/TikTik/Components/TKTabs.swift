import SwiftUI

/// shadcn Tabs (segmented control). The selected pill slides between items.
struct TKTabs<Item: Hashable>: View {
    @Environment(\.palette) private var palette
    @Namespace private var pill

    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    /// Items that get a small "live" dot (the Now tab).
    var isLive: (Item) -> Bool = { _ in false }

    var body: some View {
        HStack(spacing: Space.s0_5) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = item }
                } label: {
                    HStack(spacing: Space.s1) {
                        if isLive(item) {
                            Circle().frame(width: 5, height: 5)
                        }
                        Text(title(item))
                    }
                    .font(TextStyle.control.font)
                    .foregroundStyle(isSelected ? palette.foreground : palette.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s1)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(palette.background)
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.border, lineWidth: Size.border))
                                .shadow(color: palette.shadow, radius: 1, y: 1)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(palette.muted, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

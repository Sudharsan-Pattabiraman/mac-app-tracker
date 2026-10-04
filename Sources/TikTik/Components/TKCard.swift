import SwiftUI

/// shadcn Card: card surface, 1 pt border, radius lg. Optional header (title + description) and footer.
struct TKCard<Content: View, Footer: View>: View {
    @Environment(\.palette) private var palette

    private let title: String?
    private let description: String?
    private let padding: EdgeInsets
    private let content: Content
    private let footer: Footer

    init(title: String? = nil,
         description: String? = nil,
         padding: EdgeInsets = CardPadding.standard,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.description = description
        self.padding = padding
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || description != nil {
                VStack(alignment: .leading, spacing: Space.s0_5) {
                    if let title { Text(title).textStyle(.bodyStrong) }
                    if let description { Text(description).textStyle(.label) }
                }
                .padding(.horizontal, padding.leading)
                .padding(.top, padding.top)
            }
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
            if Footer.self != EmptyView.self {
                TKSeparator()
                footer
                    .padding(.horizontal, padding.leading)
                    .padding(.vertical, Space.s2_5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .background(palette.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: Size.border)
        )
    }
}

extension TKCard where Footer == EmptyView {
    init(title: String? = nil,
         description: String? = nil,
         padding: EdgeInsets = CardPadding.standard,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, description: description, padding: padding, content: content, footer: { EmptyView() })
    }
}

enum CardPadding {
    static let standard = EdgeInsets(top: Space.s3, leading: Space.s3_5, bottom: Space.s3, trailing: Space.s3_5)
    static let list = EdgeInsets(top: 0, leading: Space.s3, bottom: 0, trailing: Space.s3)
    static let none = EdgeInsets()
}

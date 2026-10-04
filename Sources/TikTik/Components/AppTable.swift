import SwiftUI
import TikTikCore

/// Column widths from the approved design.
private enum Column {
    static let time: CGFloat = 50
    static let ram: CGFloat = 52
    static let percent: CGFloat = 30
    static let chevron: CGFloat = 8
}

enum AppSort {
    case time, memory
}

/// The App · Time · RAM · % table (SPEC 5.4).
struct AppTable: View {
    @Environment(\.palette) private var palette

    let apps: [AppUsage]
    let totalActive: TimeInterval
    @Binding var sort: AppSort
    let onSelect: (AppUsage) -> Void

    private var sortedApps: [AppUsage] {
        switch sort {
        case .time:
            return apps.sorted { $0.active > $1.active }
        case .memory:
            // Apps that aren't running go last, then by time.
            return apps.sorted {
                switch ($0.memoryBytes, $1.memoryBytes) {
                case let (a?, b?): return a > b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.active > $1.active
                }
            }
        }
    }

    var body: some View {
        TKCard(padding: CardPadding.list) {
            VStack(spacing: 0) {
                header
                TKSeparator()
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sortedApps.enumerated()), id: \.element.id) { index, app in
                            if index > 0 { TKSeparator() }
                            AppTableRow(app: app, share: totalActive > 0 ? app.active / totalActive : 0) {
                                onSelect(app)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Color.clear.frame(width: Size.appIcon, height: 1)
            Text("App").frame(maxWidth: .infinity, alignment: .leading)
            sortButton("Time", .time).frame(width: Column.time, alignment: .trailing)
            sortButton("RAM", .memory).frame(width: Column.ram, alignment: .trailing)
            Text("%").frame(width: Column.percent, alignment: .trailing)
            Color.clear.frame(width: Column.chevron, height: 1)
        }
        .textStyle(.caption)
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s1_5)
    }

    private func sortButton(_ title: String, _ key: AppSort) -> some View {
        Button {
            sort = key
        } label: {
            Text(sort == key ? "\(title) ↓" : title)
                .foregroundStyle(sort == key ? palette.foreground : palette.mutedForeground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title)")
    }
}

private struct AppTableRow: View {
    @Environment(\.palette) private var palette
    @State private var isHovering = false

    let app: AppUsage
    let share: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                AppIconView(app: app.app)
                VStack(spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        Text(app.app.name)
                            .textStyle(.bodyStrong)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(DurationFormat.short(app.active))
                            .textStyle(.bodySm)
                            .frame(width: Column.time, alignment: .trailing)
                        Text(MemoryFormat.string(app.memoryBytes))
                            .font(.custom(MemoryFormat.isHeavy(app.memoryBytes) ? Fonts.semibold : Fonts.regular,
                                          size: TextStyle.bodySm.size))
                            .foregroundStyle(MemoryFormat.isHeavy(app.memoryBytes) ? palette.foreground : palette.mutedForeground)
                            .frame(width: Column.ram, alignment: .trailing)
                        Text("\(Int((share * 100).rounded()))%")
                            .textStyle(.bodySm)
                            .foregroundStyle(palette.mutedForeground)
                            .frame(width: Column.percent, alignment: .trailing)
                    }
                    TKProgress(value: share)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.mutedForeground)
                    .frame(width: Column.chevron)
            }
            .padding(.vertical, Space.s2_5)
            .padding(.horizontal, Space.s1)
            .background(isHovering ? palette.accent.opacity(0.6) : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, -Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details for \(app.app.name)")
    }
}

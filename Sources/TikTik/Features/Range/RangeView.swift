import SwiftUI
import TikTikCore

/// A range tab (6h … 6M): ring (short ranges) or legend + chart (long ranges), then the app table.
struct RangeView: View {
    @Environment(AppState.self) private var state
    let tab: TimeTab

    @State private var summary: RangeSummary?

    private struct LoadKey: Equatable {
        let tab: TimeTab
        let revision: Int
    }

    var body: some View {
        Group {
            if let summary, summary.tab == tab {
                if summary.isEmpty {
                    emptyState
                } else {
                    content(summary)
                }
            } else {
                Color.clear
            }
        }
        .task(id: LoadKey(tab: tab, revision: state.dataRevision)) {
            summary = await state.provider.summary(for: tab, now: Date())
        }
    }

    private func content(_ summary: RangeSummary) -> some View {
        @Bindable var state = state
        return VStack(spacing: Space.s3) {
            if tab.usesRing {
                StateRingCard(active: summary.active, idle: summary.idle, away: summary.away)
            } else {
                StateLegendLine(active: summary.active, idle: summary.idle, away: summary.away)
                TKBarChart(buckets: summary.buckets, title: "Active", unitLabel: tab.bucket.unitLabel,
                           tickIndices: Self.tickIndices(count: summary.buckets.count, tab: tab))
                if let start = summary.historyStart {
                    Text("History starts \(PopoverRoot.dayFormatter.string(from: start)) · earlier \(tab == .m6 ? "weeks" : "days") have no data")
                        .textStyle(.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s0_5)
                }
            }
            AppTable(apps: summary.apps, totalActive: summary.active, sort: $state.sort) { app in
                withAnimation(.easeOut(duration: 0.15)) { state.openDetail(app.app) }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if state.provider.hasHistory {
            TKEmptyState(systemImage: nil,
                         title: "Nothing recorded \(Self.rangePhrase(tab))",
                         message: "TikTik wasn't running or tracking was paused for this whole period. Time it can't see is never counted.")
        } else {
            TKEmptyState(systemImage: "hourglass",
                         title: "Tracking has started",
                         message: "Your first few minutes will appear here shortly. Leave TikTik running; it uses almost no battery.")
        }
    }

    static func rangePhrase(_ tab: TimeTab) -> String {
        if let hours = tab.hours { return "in the last \(hours) hours" }
        if let days = tab.days { return "in the last \(days) days" }
        return ""
    }

    static func tickIndices(count: Int, tab: TimeTab) -> [Int] {
        switch count {
        case 7: return Array(0..<7)
        case 30: return [0, 10, 20, 29]
        case 26: return [0, 9, 17, 25]
        case 24: return tab == .h24 ? [0, 6, 12, 18, 23] : [0, 8, 16, 23]
        default: return count > 0 ? [0, count - 1] : []
        }
    }
}

/// Ring + legend card for 6h, 12h and 24h.
struct StateRingCard: View {
    let active: TimeInterval
    let idle: TimeInterval
    let away: TimeInterval

    var body: some View {
        TKCard(padding: EdgeInsets(top: Space.s3, leading: Space.s3, bottom: Space.s3, trailing: Space.s3_5)) {
            HStack(spacing: Space.s3_5) {
                TKRing(active: active, idle: idle, away: away)
                VStack(spacing: Space.s1_5) {
                    TKLegendItem(tone: .active, title: "Active", value: DurationFormat.short(active))
                    TKLegendItem(tone: .idle, title: "Idle", value: DurationFormat.short(idle))
                    TKLegendItem(tone: .away, title: "Away", value: DurationFormat.short(away))
                }
            }
        }
    }
}

/// One-line totals for 1W, 1M and 6M (wraps to two lines when needed).
struct StateLegendLine: View {
    @Environment(\.palette) private var palette
    let active: TimeInterval
    let idle: TimeInterval
    let away: TimeInterval

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s3_5) { items }
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s3_5) {
                    item(.active, "Active", active)
                    item(.idle, "Idle", idle)
                }
                item(.away, "Away", away)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s0_5)
    }

    @ViewBuilder
    private var items: some View {
        item(.active, "Active", active)
        item(.idle, "Idle", idle)
        item(.away, "Away", away)
    }

    private func item(_ tone: StateTone, _ title: String, _ value: TimeInterval) -> some View {
        HStack(spacing: Space.s1_5) {
            RoundedRectangle(cornerRadius: 2).fill(palette.color(for: tone)).frame(width: 8, height: 8)
            Text(title).foregroundStyle(palette.mutedForeground)
            Text(DurationFormat.short(value)).font(.custom(Fonts.medium, size: TextStyle.label.size))
        }
        .font(TextStyle.label.font)
        .fixedSize()
    }
}

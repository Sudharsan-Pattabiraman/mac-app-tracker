import AppKit
import SwiftUI
import TikTikCore

/// App detail page inside the popover (SPEC 5.6).
struct AppDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    let app: AppIdentity

    @State private var detail: AppDetail?

    private struct LoadKey: Equatable {
        let tab: TimeTab
        let revision: Int
    }

    var body: some View {
        @Bindable var state = state
        return VStack(spacing: Space.s3) {
            HStack {
                BackButton()
                Spacer()
                TKBadge(text: badgeText)
            }
            if let detail, detail.tab == state.detailTab {
                header(detail)
            } else {
                header(nil)
            }
            TKTabs(items: TimeTab.ranges, selection: $state.detailTab, title: \.label)
            ScrollView(.vertical, showsIndicators: false) {
                if let detail, detail.tab == state.detailTab {
                    content(detail)
                }
            }
        }
        .task(id: LoadKey(tab: state.detailTab, revision: state.dataRevision)) {
            detail = await state.provider.detail(for: app, tab: state.detailTab, now: Date())
        }
    }

    private var badgeText: String {
        let tab = state.detailTab
        if tab.hours != nil { return "Last \(tab.label)" }
        guard let window = tab.window(endingAt: Date()) else { return tab.label }
        return PopoverRoot.dayFormatter.string(from: window.start) + " – " + PopoverRoot.dayFormatter.string(from: Date())
    }

    private func header(_ detail: AppDetail?) -> some View {
        HStack(spacing: Space.s2_5) {
            AppIconView(app: app, size: Size.appIconLarge)
            VStack(alignment: .leading, spacing: Space.s0_5) {
                Text(app.name).textStyle(.heading).lineLimit(1)
                Text(detail.map { "\(DurationFormat.short($0.active)) active · \(Int(($0.shareOfActive * 100).rounded()))% of active time" } ?? " ")
                    .textStyle(.label)
            }
            Spacer()
        }
    }

    private func content(_ detail: AppDetail) -> some View {
        VStack(spacing: Space.s3) {
            TKBarChart(buckets: detail.buckets, title: "Usage", unitLabel: detail.tab.bucket.unitLabel,
                       tickIndices: RangeView.tickIndices(count: detail.buckets.count))
            StatGrid(items: [
                ("Sessions", "\(detail.sessions)"),
                ("Longest", DurationFormat.short(detail.longestSession)),
                ("First · Last used", firstLast(detail)),
                ("RAM now", MemoryFormat.string(detail.memoryBytes)),
            ])
            if detail.domainAccessDenied {
                accessDeniedCard
            } else if let domains = detail.domains, !domains.isEmpty {
                domainsCard(domains, total: detail.active)
            }
        }
    }

    private func firstLast(_ detail: AppDetail) -> String {
        guard let first = detail.firstUsed, let last = detail.lastUsed else { return "—" }
        let formatter = detail.tab.hours != nil ? PopoverRoot.timeFormatter : PopoverRoot.dayFormatter
        return formatter.string(from: first) + " · " + formatter.string(from: last)
    }

    private func domainsCard(_ domains: [DomainUsage], total: TimeInterval) -> some View {
        TKCard(padding: CardPadding.list) {
            VStack(spacing: 0) {
                HStack {
                    Text("Top domains")
                    Spacer()
                    Text("% of \(app.name)")
                }
                .textStyle(.label)
                .padding(.top, Space.s2_5)
                .padding(.bottom, Space.s1)
                ForEach(Array(domains.enumerated()), id: \.element.id) { index, domain in
                    if index > 0 { TKSeparator() }
                    let share = total > 0 ? domain.active / total : 0
                    VStack(spacing: Space.s1) {
                        HStack(spacing: Space.s2_5) {
                            Text(domain.domain)
                                .textStyle(.bodySm)
                                .foregroundStyle(domain.domain == DomainUsage.privateBrowsing ? palette.mutedForeground : palette.foreground)
                                .lineLimit(1)
                            Spacer()
                            Text(DurationFormat.short(domain.active)).textStyle(.bodySm)
                            Text("\(Int((share * 100).rounded()))%")
                                .textStyle(.bodySm)
                                .foregroundStyle(palette.mutedForeground)
                                .frame(width: 34, alignment: .trailing)
                        }
                        TKProgress(value: share, thin: true)
                    }
                    .padding(.vertical, Space.s2)
                }
            }
        }
    }

    private var accessDeniedCard: some View {
        TKCard {
            VStack(alignment: .leading, spacing: Space.s2_5) {
                HStack {
                    Text("Top domains").textStyle(.bodyStrong)
                    Spacer()
                    TKBadge(text: "No access", variant: .destructive)
                }
                Text("TikTik isn't allowed to read \(app.name)'s address bar, so only app time is recorded. Allow it in System Settings → Privacy & Security → Automation.")
                    .textStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.tk(.outline, size: .small))
            }
        }
    }
}

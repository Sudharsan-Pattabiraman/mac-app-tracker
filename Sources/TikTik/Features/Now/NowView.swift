import SwiftUI
import TikTikCore

/// The live Now tab (SPEC 5.5).
struct NowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @State private var snapshot: NowSnapshot?
    @State private var loaded = false

    var body: some View {
        Group {
            if let snapshot {
                VStack(spacing: Space.s3) {
                    currentCard(snapshot)
                    recentCard(snapshot.recent)
                }
            } else if loaded {
                TKEmptyState(systemImage: "hourglass",
                             title: "Tracking has started",
                             message: "Switch to any app and it shows up here, live.")
            } else {
                Color.clear
            }
        }
        .task(id: state.dataRevision) {
            snapshot = await state.provider.nowSnapshot(at: Date())
            loaded = true
        }
    }

    // MARK: Current app

    private func currentCard(_ now: NowSnapshot) -> some View {
        TKCard(padding: EdgeInsets(top: Space.s3_5, leading: Space.s3_5, bottom: Space.s3_5, trailing: Space.s3_5)) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    AppIconView(app: now.app, size: Size.appIconHero)
                    VStack(alignment: .leading, spacing: Space.s0_5) {
                        Text(now.app?.name ?? "—").textStyle(.heading).lineLimit(1)
                        Text("frontmost app").textStyle(.label)
                    }
                    Spacer(minLength: Space.s2)
                    TKBadge(text: now.state == .idle ? "Idle" : "Active",
                            dot: now.state == .idle ? palette.stateIdle : palette.stateActive)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(DurationFormat.timer(context.date.timeIntervalSince(now.since)))
                            .textStyle(.hero)
                            .lineLimit(1)
                            .fixedSize()
                        Text((now.state == .idle ? "idle since " : "since ") + PopoverRoot.timeFormatter.string(from: now.since))
                            .textStyle(.label)
                            .lineLimit(1)
                    }
                }

                if let site = now.site {
                    HStack {
                        Text(site).font(.custom(Fonts.medium, size: TextStyle.bodySm.size))
                        Spacer()
                        if let siteSince = now.siteSince {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("\(DurationFormat.timer(context.date.timeIntervalSince(siteSince))) on this site")
                                    .textStyle(.label)
                            }
                        }
                    }
                    .padding(.horizontal, Space.s2_5)
                    .padding(.vertical, Space.s2)
                    .background(palette.muted, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }

                StatGrid(items: [
                    ("Today in this app", DurationFormat.short(now.todayInApp)),
                    ("RAM now", MemoryFormat.string(now.memoryBytes)),
                ])
            }
        }
    }

    // MARK: Recent

    private func recentCard(_ recent: [Stretch]) -> some View {
        TKCard(padding: CardPadding.list) {
            VStack(spacing: 0) {
                HStack {
                    Text("Recent")
                    Spacer()
                    Text("today")
                }
                .textStyle(.label)
                .padding(.top, Space.s2_5)
                .padding(.bottom, Space.s1)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, stretch in
                            if index > 0 { TKSeparator() }
                            HStack(spacing: Space.s2) {
                                Text(PopoverRoot.timeFormatter.string(from: stretch.start))
                                    .textStyle(.label)
                                    .frame(width: 44, alignment: .leading)
                                AppIconView(app: stretch.app)
                                Text(stretch.app?.name ?? "Idle")
                                    .textStyle(stretch.app == nil ? .bodySm : .bodyStrong)
                                    .foregroundStyle(stretch.app == nil ? palette.mutedForeground : palette.foreground)
                                    .lineLimit(1)
                                Spacer()
                                Text(DurationFormat.short(stretch.duration))
                                    .textStyle(.bodySm)
                                    .foregroundStyle(stretch.app == nil ? palette.mutedForeground : palette.foreground)
                            }
                            .padding(.vertical, Space.s2)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Two-column grid of label/value pairs separated by 1 pt borders (Now, app detail).
struct StatGrid: View {
    @Environment(\.palette) private var palette
    let items: [(String, String)]

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex > 0 { TKSeparator() }
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, item in
                        if columnIndex > 0 { TKSeparator(vertical: true) }
                        VStack(alignment: .leading, spacing: Space.s0_5) {
                            Text(item.0).textStyle(.label)
                            Text(item.1).textStyle(.bodyStrong)
                        }
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(palette.card, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.border, lineWidth: Size.border))
    }
}

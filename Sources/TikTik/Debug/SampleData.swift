import Foundation
import TikTikCore

/// Design-review scenarios for `--sample-data` (switchable from the Design Review window).
enum SampleScenario: String, CaseIterable, Identifiable {
    case normal, nowChrome, nowIdle, firstLaunch, nothingRecorded, partialHistory, chromeDenied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal · Now in Xcode"
        case .nowChrome: return "Now in Chrome"
        case .nowIdle: return "Now idle"
        case .firstLaunch: return "Empty · first launch"
        case .nothingRecorded: return "Empty · nothing recorded"
        case .partialHistory: return "Partial history (1W/1M/6M)"
        case .chromeDenied: return "Chrome access denied"
        }
    }
}

/// Deterministic example data matching the approved mockups (design/tiktik-design.html).
@MainActor
final class SampleUsageProvider: UsageProvider {
    var scenario: SampleScenario

    init(scenario: SampleScenario = .normal) {
        self.scenario = scenario
    }

    // MARK: Example apps (share of Active time, live RAM in MB)

    static let xcode = AppIdentity(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    static let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
    static let slack = AppIdentity(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    static let figma = AppIdentity(bundleID: "com.figma.Desktop", name: "Figma")
    static let terminal = AppIdentity(bundleID: "com.apple.Terminal", name: "Terminal")
    static let music = AppIdentity(bundleID: "com.apple.Music", name: "Music")

    private static let apps: [(app: AppIdentity, share: Double, memoryMB: UInt64?)] = [
        (xcode, 0.392, 2150),
        (chrome, 0.269, 3480),
        (slack, 0.140, 612),
        (figma, 0.091, nil),
        (terminal, 0.079, 88),
        (music, 0.029, 141),
    ]

    private static let domains: [(String, Double)] = [
        ("github.com", 38), ("google.com", 21), ("stackoverflow.com", 14),
        ("youtube.com", 9), (DomainUsage.privateBrowsing, 6), ("4 others", 4),
    ]

    /// Active / Idle / Away minutes per tab, as in the mockups.
    private static let totals: [TimeTab: (active: Double, idle: Double, away: Double)] = [
        .h6: (214, 22, 124),
        .h12: (302, 41, 377),
        .h24: (342, 48, 1050),
        .w1: (2289, 330, 7461),
        .m1: (9420, 1310, 32470),
        .m6: (48000, 7200, 206880),
    ]

    // MARK: UsageProvider

    var hasHistory: Bool { scenario != .firstLaunch }

    func activeToday(now: Date) -> TimeInterval {
        scenario == .firstLaunch ? 0 : 342 * 60
    }

    func summary(for tab: TimeTab, now: Date) async -> RangeSummary {
        let window = tab.window(endingAt: now) ?? DateInterval(start: now, end: now)
        let isEmpty = scenario == .firstLaunch || (scenario == .nothingRecorded && tab.hours != nil)
        guard !isEmpty, var totals = Self.totals[tab] else {
            return RangeSummary(tab: tab, window: window, active: 0, idle: 0, away: 0,
                                buckets: [], apps: [], historyStart: nil)
        }

        var historyStart: Date?
        var buckets = Self.buckets(for: tab, now: now, activeMinutes: totals.active)
        if scenario == .partialHistory, tab.days != nil {
            // Installed three days ago: only the last three days have data.
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)) ?? now
            historyStart = start
            totals = (520, 64, 3736)
            buckets = buckets.map { bucket in
                let active: TimeInterval
                if tab == .m6 {
                    active = bucket.index == tab.bucketCount - 1 ? 520 * 60 : 0   // all in the latest week
                } else {
                    active = bucket.start >= start ? 520 * 60 / 3 : 0          // spread over the last 3 days
                }
                return UsageBucket(index: bucket.index, start: bucket.start, label: bucket.label,
                                   axisLabel: bucket.axisLabel, active: active)
            }
        }

        let active = totals.active * 60
        return RangeSummary(
            tab: tab, window: window,
            active: active, idle: totals.idle * 60, away: totals.away * 60,
            buckets: buckets,
            apps: Self.apps.map { AppUsage(app: $0.app, active: active * $0.share, memoryBytes: $0.memoryMB.map { $0 * MemoryFormat.megabyte }) },
            historyStart: historyStart
        )
    }

    func nowSnapshot(at now: Date) async -> NowSnapshot? {
        guard scenario != .firstLaunch else { return nil }
        let recent: [Stretch] = [
            Stretch(start: now.addingTimeInterval(-47 * 60 - 12), duration: 47 * 60, app: Self.xcode),
            Stretch(start: now.addingTimeInterval(-53 * 60), duration: 6 * 60, app: Self.chrome),
            Stretch(start: now.addingTimeInterval(-60 * 60), duration: 7 * 60, app: nil),
            Stretch(start: now.addingTimeInterval(-81 * 60), duration: 21 * 60, app: Self.slack),
            Stretch(start: now.addingTimeInterval(-102 * 60), duration: 21 * 60, app: Self.xcode),
        ]
        switch scenario {
        case .nowChrome:
            let since = now.addingTimeInterval(-(6 * 60 + 41))
            return NowSnapshot(app: Self.chrome, state: .active, since: since,
                               site: "github.com", siteSince: now.addingTimeInterval(-(4 * 60 + 10)),
                               todayInApp: 92 * 60, memoryBytes: 3480 * MemoryFormat.megabyte,
                               recent: [Stretch(start: since, duration: 6 * 60, app: Self.chrome)] + recent.prefix(4))
        case .nowIdle:
            let since = now.addingTimeInterval(-(6 * 60 + 30))
            return NowSnapshot(app: Self.xcode, state: .idle, since: since, site: nil, siteSince: nil,
                               todayInApp: 134 * 60, memoryBytes: 2150 * MemoryFormat.megabyte,
                               recent: [Stretch(start: since, duration: 6 * 60, app: nil)] + recent.prefix(4))
        default:
            return NowSnapshot(app: Self.xcode, state: .active, since: now.addingTimeInterval(-(47 * 60 + 12)),
                               site: nil, siteSince: nil, todayInApp: 134 * 60,
                               memoryBytes: 2150 * MemoryFormat.megabyte, recent: recent)
        }
    }

    func detail(for app: AppIdentity, tab: TimeTab, now: Date) async -> AppDetail {
        let rangeSummary = await self.summary(for: tab, now: now)
        let entry = Self.apps.first { $0.app == app }
        let share = entry?.share ?? 0
        let active = rangeSummary.active * share
        let isChrome = app == Self.chrome
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return AppDetail(
            app: app, tab: tab, active: active, shareOfActive: share,
            buckets: rangeSummary.buckets.map {
                UsageBucket(index: $0.index, start: $0.start, label: $0.label, axisLabel: $0.axisLabel,
                            active: ($0.active * share * 1.6).rounded())
            },
            sessions: isChrome ? 9 : 6,
            longestSession: isChrome ? 34 * 60 : 52 * 60,
            firstUsed: calendar.date(byAdding: .minute, value: isChrome ? -(22 * 60 + 58) : -(22 * 60 + 50), to: today.addingTimeInterval(14 * 3600)),
            lastUsed: now.addingTimeInterval(isChrome ? -26 * 60 : -9 * 60),
            memoryBytes: entry?.memoryMB.map { $0 * MemoryFormat.megabyte },
            domains: isChrome && scenario != .chromeDenied
                ? Self.domains.map { DomainUsage(domain: $0.0, active: active * $0.1 / 92) }
                : nil,
            domainAccessDenied: isChrome && scenario == .chromeDenied
        )
    }

    // MARK: Buckets

    private static func buckets(for tab: TimeTab, now: Date, activeMinutes: Double) -> [UsageBucket] {
        let calendar = Calendar.current
        let count = tab.bucketCount
        var starts: [Date] = []
        var labels: [(String, String)] = []

        switch tab.bucket {
        case .minutes(let minutes):
            let step = Double(minutes * 60)
            let aligned = floor(now.timeIntervalSinceReferenceDate / step) * step
            for i in 0..<count {
                let start = Date(timeIntervalSinceReferenceDate: aligned - Double(count - 1 - i) * step)
                starts.append(start)
                let hm = Self.format(start, "HH:mm")
                labels.append((hm, i == count - 1 ? "now" : String(hm.prefix(2))))
            }
        case .day:
            let today = calendar.startOfDay(for: now)
            for i in 0..<count {
                let start = calendar.date(byAdding: .day, value: -(count - 1 - i), to: today)!
                starts.append(start)
                if tab == .w1 {
                    labels.append((Self.format(start, "EEE d"), Self.format(start, "EEE")))
                } else {
                    labels.append((Self.format(start, "MMM d"), Self.format(start, "MMM d")))
                }
            }
        case .week:
            let today = calendar.startOfDay(for: now)
            for i in 0..<count {
                let start = calendar.date(byAdding: .day, value: -7 * (count - 1 - i), to: today)!
                starts.append(start)
                labels.append(("Week of " + Self.format(start, "MMM d"), Self.format(start, "MMM")))
            }
        }

        // Deterministic shape: daytime activity, quiet nights, lighter weekends.
        var shape: [Double] = (0..<count).map { i in
            let wave = 0.35 + 0.6 * abs(sin(Double(i) * 1.7 + Double(count)))
            switch tab.bucket {
            case .minutes:
                let hour = calendar.component(.hour, from: starts[i])
                return (hour >= 1 && hour < 8) ? 0 : wave
            case .day:
                let weekday = calendar.component(.weekday, from: starts[i])
                return (weekday == 1 || weekday == 7) ? wave * 0.15 : wave
            case .week:
                return wave
            }
        }
        let sum = shape.reduce(0, +)
        if sum > 0 { shape = shape.map { $0 / sum * activeMinutes } }

        let bucketMinutes: Double
        switch tab.bucket {
        case .minutes(let m): bucketMinutes = Double(m)
        case .day: bucketMinutes = 24 * 60
        case .week: bucketMinutes = 7 * 24 * 60
        }

        return (0..<count).map { i in
            UsageBucket(index: i, start: starts[i], label: labels[i].0, axisLabel: labels[i].1,
                        active: min(shape[i], bucketMinutes) * 60)
        }
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

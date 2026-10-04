import Foundation
import TikTikCore

/// Where the popover gets its numbers. Sample data implements it in M1; the real tracker from M3.
@MainActor
protocol UsageProvider: AnyObject {
    /// False before anything has ever been recorded (first-launch empty state).
    var hasHistory: Bool { get }
    func summary(for tab: TimeTab, now: Date) async -> RangeSummary
    func nowSnapshot(at now: Date) async -> NowSnapshot?
    func detail(for app: AppIdentity, tab: TimeTab, now: Date) async -> AppDetail
    /// Active time since local midnight, for the menu bar.
    func activeToday(now: Date) -> TimeInterval
}

/// Used until real tracking exists (M2/M3): reports no data, so the first-launch state shows.
@MainActor
final class EmptyUsageProvider: UsageProvider {
    var hasHistory: Bool { false }

    func summary(for tab: TimeTab, now: Date) async -> RangeSummary {
        RangeSummary(tab: tab,
                     window: tab.window(endingAt: now) ?? DateInterval(start: now, end: now),
                     active: 0, idle: 0, away: 0, buckets: [], apps: [], historyStart: nil)
    }

    func nowSnapshot(at now: Date) async -> NowSnapshot? { nil }

    func detail(for app: AppIdentity, tab: TimeTab, now: Date) async -> AppDetail {
        AppDetail(app: app, tab: tab, active: 0, shareOfActive: 0, buckets: [], sessions: 0,
                  longestSession: 0, firstUsed: nil, lastUsed: nil, memoryBytes: nil,
                  domains: nil, domainAccessDenied: false)
    }

    func activeToday(now: Date) -> TimeInterval { 0 }
}

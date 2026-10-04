import Foundation
import TikTikCore

/// Builds what the popover shows from stored intervals plus the live (not yet stored) interval.
/// RAM is filled in by the app layer; everything else is computed here.
public struct UsageQueries: Sendable {
    public let store: TrackerStore
    public let calendar: Calendar
    /// Stretch / session gap (SPEC 5.5).
    public var gap: TimeInterval = 120
    /// Visits to another app shorter than this don't end a stretch or session (SPEC 5.5).
    public var briefVisit: TimeInterval = 30

    public init(store: TrackerStore, calendar: Calendar) {
        self.store = store
        self.calendar = calendar
    }

    // MARK: Ranges

    public func summary(tab: TimeTab, now: Date, live: TrackedInterval?) throws -> RangeSummary {
        let window = tab.window(endingAt: now, calendar: calendar) ?? DateInterval(start: now, end: now)
        let layout = BucketLayout(tab: tab, now: now, calendar: calendar)
        let intervals = try contributions(tab: tab, window: window, live: live)
        let totals = Aggregator.totals(intervals)
        let apps = Aggregator.activeByApp(intervals).map { AppUsage(app: $0.app, active: $0.active, memoryBytes: nil) }
        return RangeSummary(
            tab: tab, window: window,
            active: totals.active, idle: totals.idle, away: totals.away,
            buckets: Aggregator.buckets(intervals, layout: layout),
            apps: apps,
            historyStart: try historyStart(in: window, live: live)
        )
    }

    public func detail(app: AppIdentity, tab: TimeTab, now: Date, live: TrackedInterval?,
                       domainAccessDenied: Bool = false) throws -> AppDetail {
        let window = tab.window(endingAt: now, calendar: calendar) ?? DateInterval(start: now, end: now)
        let layout = BucketLayout(tab: tab, now: now, calendar: calendar)
        let intervals = try contributions(tab: tab, window: window, live: live)
        let totals = Aggregator.totals(intervals)
        let appActive = Aggregator.activeByApp(intervals).first { $0.app == app }?.active ?? 0

        // Sessions need real start/end times, so read the actual Active intervals.
        var active = Aggregator.clip(try store.intervals(overlapping: window, states: [.active]), to: window)
        if let liveActive = live?.clipped(to: window), liveActive.state == .active { active.append(liveActive) }
        let sessions = Aggregator.sessions(active, app: app, gap: gap, brief: briefVisit)
        let appIntervals = active.filter { $0.app == app }

        return AppDetail(
            app: app, tab: tab,
            active: appActive,
            shareOfActive: totals.active > 0 ? appActive / totals.active : 0,
            buckets: Aggregator.buckets(intervals, layout: layout, app: app),
            sessions: sessions.count,
            longestSession: sessions.map(\.active).max() ?? 0,
            firstUsed: appIntervals.map(\.start).min(),
            lastUsed: appIntervals.map(\.end).max(),
            memoryBytes: nil,
            domains: Aggregator.activeByDomain(intervals, app: app),
            domainAccessDenied: domainAccessDenied
        )
    }

    // MARK: Now tab and menu bar

    /// Today's stretches and idle periods, newest first.
    public func recentStretches(now: Date, live: TrackedInterval?) throws -> [Stretch] {
        let today = DateInterval(start: calendar.startOfDay(for: now), end: now)
        var intervals = Aggregator.clip(try store.intervals(overlapping: today), to: today)
        if let live = live?.clipped(to: today) { intervals.append(live) }
        return Aggregator.stretches(intervals, gap: gap, brief: briefVisit)
    }

    /// Active time since local midnight, overall or for one app.
    public func activeToday(now: Date, live: TrackedInterval?, app: AppIdentity? = nil) throws -> TimeInterval {
        let todayKey = DaySplitter.dayKey(now, calendar: calendar)
        var total = try store.dailyRollup(fromDay: todayKey, throughDay: todayKey)
            .filter { $0.state == .active && (app == nil || $0.app == app) }
            .reduce(0) { $0 + $1.seconds }
        let today = DateInterval(start: calendar.startOfDay(for: now), end: now)
        if let live = live?.clipped(to: today), live.state == .active, app == nil || live.app == app {
            total += live.duration
        }
        return total
    }

    // MARK: Internals

    /// Intervals inside the window. Day-based tabs use the per-day rollup (one synthetic interval per
    /// day/state/app/domain starting at that day's midnight), which is all their charts need.
    private func contributions(tab: TimeTab, window: DateInterval, live: TrackedInterval?) throws -> [TrackedInterval] {
        var intervals: [TrackedInterval]
        if tab.days != nil {
            let first = DaySplitter.dayKey(window.start, calendar: calendar)
            let last = DaySplitter.dayKey(window.end, calendar: calendar)
            intervals = try store.dailyRollup(fromDay: first, throughDay: last).compactMap { row in
                guard let dayStart = DaySplitter.date(fromDayKey: row.day, calendar: calendar) else { return nil }
                return TrackedInterval(start: dayStart, end: dayStart.addingTimeInterval(row.seconds),
                                       state: row.state, app: row.app, domain: row.domain)
            }
        } else {
            intervals = Aggregator.clip(try store.intervals(overlapping: window), to: window)
        }
        if let live = live?.clipped(to: window) { intervals.append(live) }
        return intervals
    }

    private func historyStart(in window: DateInterval, live: TrackedInterval?) throws -> Date? {
        let earliest = [try store.earliestStart(), live?.start].compactMap { $0 }.min()
        guard let earliest, earliest > window.start else { return nil }
        return calendar.startOfDay(for: earliest)
    }
}

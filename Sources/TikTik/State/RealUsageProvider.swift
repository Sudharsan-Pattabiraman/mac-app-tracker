import Foundation
import os
import TikTikCore
import TikTikStore

/// Real data for the popover: queries run off the main thread; live RAM comes from the sampler.
@MainActor
final class RealUsageProvider: UsageProvider {
    private let tracker: Tracker
    private let log = Logger(subsystem: "app.tiktik", category: "queries")

    init(tracker: Tracker) {
        self.tracker = tracker
    }

    var hasHistory: Bool {
        let stored = (try? tracker.store.hasAnyData()) ?? false
        return stored || tracker.liveInterval() != nil
    }

    func summary(for tab: TimeTab, now: Date) async -> RangeSummary {
        let queries = tracker.queries
        let live = tracker.liveInterval(now: now)
        let result = await Task.detached(priority: .userInitiated) {
            Result { try queries.summary(tab: tab, now: now, live: live) }
        }.value
        switch result {
        case .success(var summary):
            summary.apps = summary.apps.map { row in
                var withMemory = row
                withMemory.memoryBytes = tracker.memory.bytes(for: row.app.bundleID)
                return withMemory
            }
            return summary
        case .failure(let error):
            log.error("Summary failed: \(error.localizedDescription, privacy: .public)")
            return RangeSummary(tab: tab, window: tab.window(endingAt: now) ?? DateInterval(start: now, end: now),
                                active: 0, idle: 0, away: 0, buckets: [], apps: [], historyStart: nil)
        }
    }

    func nowSnapshot(at now: Date) async -> NowSnapshot? {
        let engine = tracker.engine
        guard let app = engine.frontmost else { return nil }
        let queries = tracker.queries
        let live = tracker.liveInterval(now: now)
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                (recent: try queries.recentStretches(now: now, live: live),
                 today: try queries.activeToday(now: now, live: live, app: app))
            }
        }.value
        let recent = (try? result.get().recent) ?? []
        let today = (try? result.get().today) ?? 0

        let state = engine.open.state ?? .active
        let since: Date
        if state == .active, engine.stretchApp == app, let stretchStart = engine.stretchStart {
            since = stretchStart
        } else {
            since = engine.open.start
        }
        return NowSnapshot(
            app: app, state: state, since: since,
            site: state == .active ? engine.open.domain : nil,
            siteSince: state == .active ? tracker.domainSince : nil,
            todayInApp: today,
            memoryBytes: tracker.memory.bytes(for: app.bundleID),
            recent: Array(recent.prefix(20))
        )
    }

    func detail(for app: AppIdentity, tab: TimeTab, now: Date) async -> AppDetail {
        let queries = tracker.queries
        let live = tracker.liveInterval(now: now)
        let denied = tracker.browser.isDenied(app.bundleID)
        let result = await Task.detached(priority: .userInitiated) {
            Result { try queries.detail(app: app, tab: tab, now: now, live: live, domainAccessDenied: denied) }
        }.value
        var detail: AppDetail
        switch result {
        case .success(let value):
            detail = value
        case .failure(let error):
            log.error("Detail failed: \(error.localizedDescription, privacy: .public)")
            detail = AppDetail(app: app, tab: tab, active: 0, shareOfActive: 0, buckets: [], sessions: 0,
                               longestSession: 0, firstUsed: nil, lastUsed: nil, memoryBytes: nil,
                               domains: nil, domainAccessDenied: denied)
        }
        detail.memoryBytes = tracker.memory.bytes(for: app.bundleID)
        // Only supported browsers show a domains card.
        if !BrowserMonitor.isSupported(app.bundleID) {
            detail.domains = nil
            detail.domainAccessDenied = false
        }
        return detail
    }

    func activeToday(now: Date) -> TimeInterval {
        (try? tracker.queries.activeToday(now: now, live: tracker.liveInterval(now: now))) ?? 0
    }
}

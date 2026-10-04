import Foundation
import TikTikCore
import TikTikStore

/// BucketLayout, Aggregator, TrackerStore, UsageQueries and CSVExporter.
func queryChecks(_ h: inout Harness) {
    let cal = Calendars.kolkata
    let xcode = AppIdentity(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
    let slack = AppIdentity(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    func at(_ hh: Int, _ mm: Int, _ ss: Int = 0, day: Int = 3) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hh, minute: mm, second: ss))!
    }
    func active(_ app: AppIdentity, _ from: Date, _ to: Date, _ domain: String? = nil) -> TrackedInterval {
        TrackedInterval(start: from, end: to, state: .active, app: app, domain: domain)
    }
    let now = at(14, 7)

    h.group("BucketLayout") { h in
        let h6 = BucketLayout(tab: .h6, now: now, calendar: cal)
        h.equal(h6.slots.count, 24)
        h.equal(h6.slots.last?.start, at(14, 0), "last 15-min slot starts on the quarter hour")
        h.equal(h6.slots.first?.start, at(8, 15))
        h.equal(h6.slots.last?.axisLabel, "now")
        h.equal(h6.slots[0].label, "08:15")
        let h24 = BucketLayout(tab: .h24, now: now, calendar: cal)
        h.equal(h24.slots.last?.start, at(14, 0), "hour slots align to local hours (+05:30 zone)")
        h.equal(h24.slots.first?.label, "15:00")
        let w1 = BucketLayout(tab: .w1, now: now, calendar: cal)
        h.equal(w1.slots.map(\.axisLabel), ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        h.equal(w1.slots.last?.label, "Sat 3")
        let m6 = BucketLayout(tab: .m6, now: now, calendar: cal)
        h.equal(m6.slots.count, 26)
        h.equal(m6.slots.first?.start, TimeTab.m6.window(endingAt: now, calendar: cal)?.start, "weeks cover the 182-day window")
        h.equal(m6.slots.last?.end, at(0, 0, day: 4))
        h.equal(m6.index(of: at(10, 0)), 25)
        h.equal(m6.index(of: at(10, 0, day: 5)), nil, "after the last slot")
    }

    h.group("Aggregator") { h in
        let intervals = [
            active(xcode, at(9, 0), at(10, 0)),
            active(chrome, at(10, 0), at(10, 30), "github.com"),
            active(chrome, at(10, 30), at(10, 45), "google.com"),
            TrackedInterval(start: at(10, 45), end: at(11, 0), state: .idle),
            active(xcode, at(11, 0), at(11, 20)),
            TrackedInterval(start: at(11, 20), end: at(12, 0), state: .away),
        ]
        let totals = Aggregator.totals(intervals)
        h.equal(totals, Aggregator.Totals(active: 7_500, idle: 900, away: 2_400))
        let apps = Aggregator.activeByApp(intervals)
        h.equal(apps.map(\.app), [xcode, chrome], "most-used first")
        h.equal(apps.map(\.active), [4_800, 2_700])
        h.equal(Aggregator.activeByDomain(intervals, app: chrome).map(\.domain), ["github.com", "google.com"])

        let window = DateInterval(start: at(9, 30), end: at(10, 15))
        h.equal(Aggregator.totals(Aggregator.clip(intervals, to: window)).active, 2_700, "clipping")

        let layout = BucketLayout(tab: .h24, now: now, calendar: cal)
        let buckets = Aggregator.buckets(intervals, layout: layout)
        let nine = buckets.first { $0.label == "09:00" }?.active
        let ten = buckets.first { $0.label == "10:00" }?.active
        let eleven = buckets.first { $0.label == "11:00" }?.active
        h.equal([nine, ten, eleven], [3_600, 2_700, 1_200], "spread across hours")
        h.equal(Aggregator.buckets(intervals, layout: layout, app: chrome).map(\.active).reduce(0, +), 2_700, "one app")

        // Sessions: Xcode 9-10, then Chrome in between, then Xcode again → 2 sessions.
        let sessions = Aggregator.sessions(intervals, app: xcode, gap: 120)
        h.equal(sessions.count, 2)
        h.equal(sessions.map(\.active), [3_600, 1_200])
        let gapped = [active(xcode, at(9, 0), at(9, 10)), active(xcode, at(9, 11), at(9, 20)), active(xcode, at(9, 30), at(9, 40))]
        h.equal(Aggregator.sessions(gapped, app: xcode, gap: 120).map(\.active), [1_140, 600], "1 min gap joins, 10 min splits")

        let stretches = Aggregator.stretches(intervals + [TrackedInterval(start: at(12, 0), end: at(12, 1), state: .idle),
                                                          active(slack, at(12, 1), at(12, 10))], gap: 120)
        h.equal(stretches.map { $0.app?.name ?? "Idle" }, ["Slack", "Xcode", "Idle", "Google Chrome", "Xcode"],
                "newest first; short idle hidden; away hidden")
        h.equal(stretches.first { $0.app == chrome }?.duration, 2_700, "domains don't break a stretch")
    }

    h.group("TrackerStore") { h in
        let path = NSTemporaryDirectory() + "tiktik-checks-\(UUID().uuidString).sqlite"
        defer { ["", "-wal", "-shm"].forEach { try? FileManager.default.removeItem(atPath: path + $0) } }
        guard let store = try? TrackerStore(path: path) else {
            h.expect(false, "store opens")
            return
        }
        do {
            h.expect(try !store.hasAnyData(), "empty at first")
            try store.append([
                active(xcode, at(23, 0, day: 2), at(1, 0)),           // crosses midnight → 2 rows
                active(chrome, at(9, 0), at(9, 30), "github.com"),
                TrackedInterval(start: at(9, 30), end: at(9, 40), state: .idle),
            ], calendar: cal)
            h.expect(try store.hasAnyData(), "has data after append")
            let day3 = try store.intervals(overlapping: DateInterval(start: at(0, 0), end: at(0, 0, day: 4)))
            h.equal(day3.count, 3, "midnight split stored as separate rows")
            h.equal(day3.first?.start, at(0, 0), "row starts at midnight")
            h.equal(day3[1].domain, "github.com")
            h.equal(try store.earliestStart(), at(23, 0, day: 2))

            let rollup = try store.dailyRollup(fromDay: 20261003, throughDay: 20261003)
            h.equal(rollup.filter { $0.state == .active }.map(\.seconds).reduce(0, +), 5_400, "rollup active seconds")

            // Late idle: 9:20–9:30 of the Chrome row becomes idle.
            try store.reclassifyAsIdle(DateInterval(start: at(9, 20), end: at(9, 35)))
            let after = try store.intervals(overlapping: DateInterval(start: at(9, 0), end: at(10, 0)))
            h.equal(after.map(\.state), [.active, .idle, .idle], "split into active + idle; idle row untouched")
            h.equal(after.first?.end, at(9, 20))
            h.equal(after.first?.domain, "github.com", "kept part keeps its domain")

            // Crash recovery.
            try store.checkpoint(active(slack, at(10, 0), at(10, 5)))
            let recovered = try store.recoverOpenInterval(calendar: cal)
            h.equal(recovered?.app, slack, "checkpoint recovered")
            h.equal(try store.recoverOpenInterval(calendar: cal), nil, "only once")
            h.equal(try store.intervals(overlapping: DateInterval(start: at(10, 0), end: at(11, 0))).count, 1)

            // Retention keeps 182 days including today.
            try store.append([TrackedInterval(start: at(9, 0, day: 1).addingTimeInterval(-200 * 86_400),
                                              end: at(9, 30, day: 1).addingTimeInterval(-200 * 86_400), state: .idle)], calendar: cal)
            h.equal(try store.applyRetention(now: now, calendar: cal), 1, "old row deleted")
            h.equal(try store.earliestStart(), at(23, 0, day: 2), "recent rows kept")

            // CSV
            let csv = try CSVExporter(store: store, calendar: cal).export(.raw, window: DateInterval(start: at(9, 0), end: at(9, 20)))
            h.equal(csv, "start,end,duration_seconds,state,app,bundle_id,domain\n2026-10-03T09:00:00+05:30,2026-10-03T09:20:00+05:30,1200,active,Google Chrome,com.google.Chrome,github.com\n")
            let daily = try CSVExporter(store: store, calendar: cal).export(.daily, window: DateInterval(start: at(0, 0), end: now))
            h.expect(daily.hasPrefix("date,state,app,bundle_id,domain,seconds\n2026-10-03,"), "daily header and rows")
            h.equal(CSVExporter.row(["a,b", "say \"hi\"", "plain"]), "\"a,b\",\"say \"\"hi\"\"\",plain", "CSV quoting")

            try store.deleteAll()
            h.expect(try !store.hasAnyData(), "clear all")
        } catch {
            h.expect(false, "store error: \(error)")
        }
    }

    h.group("UsageQueries") { h in
        guard let store = try? TrackerStore(path: nil) else {
            h.expect(false, "in-memory store opens")
            return
        }
        do {
            try store.append([
                active(xcode, at(9, 0), at(10, 0)),
                active(chrome, at(10, 0), at(10, 30), "github.com"),
                TrackedInterval(start: at(10, 30), end: at(11, 0), state: .idle),
                active(xcode, at(11, 0), at(12, 0)),
                active(slack, at(9, 0, day: 1), at(9, 45, day: 1)),
            ], calendar: cal)
            let queries = UsageQueries(store: store, calendar: cal)
            let live = active(xcode, at(14, 0), now)

            let h6 = try queries.summary(tab: .h6, now: now, live: live)
            h.equal(h6.active, 3_600 + 1_800 + 3_600 + 420, "6h window (08:07–14:07) plus the live interval")
            h.equal(h6.apps.first?.app, xcode)

            let week = try queries.summary(tab: .w1, now: now, live: live)
            h.equal(week.active, 3_600 + 1_800 + 3_600 + 2_700 + 420, "1W uses daily rollup + live")
            h.equal(week.idle, 1_800)
            h.equal(week.buckets.count, 7)
            h.equal(week.buckets.last?.active, 3_600 + 1_800 + 3_600 + 420, "today's bucket")
            h.equal(week.buckets[4].active, 2_700, "Oct 1 bucket")
            h.equal(week.historyStart, at(0, 0, day: 1), "history starts Oct 1")
            h.equal(week.apps.map(\.app), [xcode, slack, chrome])

            let detail = try queries.detail(app: chrome, tab: .h24, now: now, live: live)
            h.equal(detail.active, 1_800)
            h.equal(detail.sessions, 1)
            h.equal(detail.domains?.map(\.domain), ["github.com"])
            h.equal(detail.firstUsed, at(10, 0))
            let xcodeDetail = try queries.detail(app: xcode, tab: .h24, now: now, live: live)
            h.equal(xcodeDetail.sessions, 3, "9–10, 11–12 and the live one")
            h.equal(xcodeDetail.longestSession, 3_600)
            h.equal(xcodeDetail.lastUsed, now, "live interval counts")

            h.equal(try queries.activeToday(now: now, live: live), 3_600 + 1_800 + 3_600 + 420)
            h.equal(try queries.activeToday(now: now, live: live, app: chrome), 1_800)

            let recent = try queries.recentStretches(now: now, live: live)
            h.equal(recent.map { $0.app?.name ?? "Idle" }, ["Xcode", "Xcode", "Idle", "Google Chrome", "Xcode"])
        } catch {
            h.expect(false, "query error: \(error)")
        }
    }
}

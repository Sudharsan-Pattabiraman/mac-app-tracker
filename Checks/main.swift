import Foundation
import TikTikCore

var h = Harness()

h.group("smoke") { h in
    h.expect(!TikTikCore.version.isEmpty, "version is set")
}

h.group("DurationFormat.short") { h in
    h.equal(DurationFormat.short(0), "<1m", "zero")
    h.equal(DurationFormat.short(59), "<1m", "under a minute")
    h.equal(DurationFormat.short(60), "1m")
    h.equal(DurationFormat.short(47 * 60 + 59), "47m", "partial minutes truncate")
    h.equal(DurationFormat.short(3600), "1h 00m", "pads minutes when hours present")
    h.equal(DurationFormat.short(6 * 3600 + 6 * 60), "6h 06m")
    h.equal(DurationFormat.short(2 * 3600 + 14 * 60), "2h 14m")
    h.equal(DurationFormat.short(38 * 3600 + 12 * 60), "38h 12m", "stays in hours past 24h")
    h.equal(DurationFormat.short(-5), "<1m", "negative clamps")
}

h.group("DurationFormat.timer") { h in
    h.equal(DurationFormat.timer(0), "0m 00s")
    h.equal(DurationFormat.timer(47 * 60 + 12), "47m 12s")
    h.equal(DurationFormat.timer(6 * 60 + 41), "6m 41s")
    h.equal(DurationFormat.timer(3600 + 2 * 60 + 5), "1h 02m", "drops seconds from an hour")
}

h.group("MemoryFormat") { h in
    let mb = MemoryFormat.megabyte, gb = MemoryFormat.gigabyte
    h.equal(MemoryFormat.string(nil), "—", "not running")
    h.equal(MemoryFormat.string(88 * mb), "88 MB")
    h.equal(MemoryFormat.string(612 * mb), "612 MB")
    h.equal(MemoryFormat.string(100), "1 MB", "tiny values show at least 1 MB")
    h.equal(MemoryFormat.string(gb), "1.0 GB")
    h.equal(MemoryFormat.string(gb * 21 / 10), "2.1 GB")
    h.equal(MemoryFormat.string(3480 * mb), "3.4 GB")
    h.expect(!MemoryFormat.isHeavy(nil), "nil isn't heavy")
    h.expect(!MemoryFormat.isHeavy(2 * gb - 1), "just under 2 GB isn't heavy")
    h.expect(MemoryFormat.isHeavy(2 * gb), "2 GB is heavy")
}

h.group("TimeTab") { h in
    h.equal(TimeTab.allCases.map(\.label), ["Now", "6h", "12h", "24h", "1W", "1M", "6M"], "tab order")
    h.equal(TimeTab.ranges.count, 6)
    h.expect(TimeTab.h24.usesRing && !TimeTab.w1.usesRing, "ring only for short ranges")
    h.equal(TimeTab.h24.bucket, .minutes(60))
    h.equal(TimeTab.h24.bucket.unitLabel, "hour")
    h.equal(TimeTab.h6.bucket.unitLabel, "15 min")
    h.equal(TimeTab.m6.bucket, .week)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 14, minute: 7))!
    h.equal(TimeTab.h6.window(endingAt: now, calendar: calendar)?.duration, 6 * 3600, "6h window")
    let week = TimeTab.w1.window(endingAt: now, calendar: calendar)!
    h.equal(week.start, calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!, "1W starts 6 days before today at midnight")
    let half = TimeTab.m6.window(endingAt: now, calendar: calendar)!
    h.equal(calendar.dateComponents([.day], from: half.start, to: calendar.startOfDay(for: now)).day, 181, "6M covers 182 days incl. today")
    h.expect(TimeTab.now.window(endingAt: now, calendar: calendar) == nil, "Now has no window")
}

engineChecks(&h)
queryChecks(&h)
domainChecks(&h)

exit(h.report())

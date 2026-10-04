import Foundation

/// Splits intervals at local midnight (SPEC 2.6) and converts dates to day keys (yyyymmdd).
public enum DaySplitter {
    /// Pieces of `interval` that each lie within one local day.
    public static func split(_ interval: TrackedInterval, calendar: Calendar) -> [TrackedInterval] {
        guard interval.end > interval.start else { return [] }
        var pieces: [TrackedInterval] = []
        var cursor = interval.start
        while cursor < interval.end {
            let next = nextMidnight(after: cursor, calendar: calendar)
            var piece = interval
            piece.start = cursor
            piece.end = min(next, interval.end)
            pieces.append(piece)
            cursor = piece.end
        }
        return pieces
    }

    /// The first local midnight strictly after `date`.
    public static func nextMidnight(after date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        // Adding a day to the start of day handles DST days of 23 or 25 hours.
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(86_400)
    }

    /// Day key for the local day containing `date`, e.g. 20261003.
    public static func dayKey(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Local midnight starting the day with this key.
    public static func date(fromDayKey key: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: key / 10_000, month: (key / 100) % 100, day: key % 100)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }
}

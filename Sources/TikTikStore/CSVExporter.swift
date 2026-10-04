import Foundation
import TikTikCore

/// CSV export (SPEC 4): raw intervals or daily totals for a date range.
public struct CSVExporter: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case raw
        case daily
    }

    public let store: TrackerStore
    public let calendar: Calendar

    public init(store: TrackerStore, calendar: Calendar) {
        self.store = store
        self.calendar = calendar
    }

    public func export(_ kind: Kind, window: DateInterval) throws -> String {
        switch kind {
        case .raw: return try raw(window: window)
        case .daily: return try daily(window: window)
        }
    }

    /// One row per interval: start, end (ISO 8601 with offset), duration, state, app, bundle id, domain.
    private func raw(window: DateInterval) throws -> String {
        let timestamp = ISO8601DateFormatter()
        timestamp.timeZone = calendar.timeZone
        timestamp.formatOptions = [.withInternetDateTime]
        var lines = ["start,end,duration_seconds,state,app,bundle_id,domain"]
        for interval in Aggregator.clip(try store.intervals(overlapping: window), to: window) {
            lines.append(Self.row([
                timestamp.string(from: interval.start),
                timestamp.string(from: interval.end),
                String(Int(interval.duration.rounded())),
                Self.name(interval.state),
                interval.app?.name ?? "",
                interval.app?.bundleID ?? "",
                interval.domain ?? "",
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One row per day, state, app and domain.
    private func daily(window: DateInterval) throws -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        date.dateFormat = "yyyy-MM-dd"
        let first = DaySplitter.dayKey(window.start, calendar: calendar)
        let last = DaySplitter.dayKey(window.end, calendar: calendar)
        var lines = ["date,state,app,bundle_id,domain,seconds"]
        for row in try store.dailyRollup(fromDay: first, throughDay: last) {
            guard let day = DaySplitter.date(fromDayKey: row.day, calendar: calendar) else { continue }
            lines.append(Self.row([
                date.string(from: day),
                Self.name(row.state),
                row.app?.name ?? "",
                row.app?.bundleID ?? "",
                row.domain ?? "",
                String(Int(row.seconds.rounded())),
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func name(_ state: ActivityState) -> String {
        switch state {
        case .active: return "active"
        case .idle: return "idle"
        case .away: return "away"
        }
    }

    /// Quotes fields containing commas, quotes or line breaks (RFC 4180).
    public static func row(_ fields: [String]) -> String {
        fields.map { field in
            guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",")
    }
}

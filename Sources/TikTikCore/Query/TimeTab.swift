import Foundation

/// The seven popover tabs (SPEC 3, 5.5). `now` is a live view; the rest are rolling windows ending now.
public enum TimeTab: String, CaseIterable, Codable, Sendable {
    case now, h6, h12, h24, w1, m1, m6

    /// The six real time ranges, used where Now doesn't apply (app detail).
    public static let ranges: [TimeTab] = [.h6, .h12, .h24, .w1, .m1, .m6]

    public var label: String {
        switch self {
        case .now: return "Now"
        case .h6: return "6h"
        case .h12: return "12h"
        case .h24: return "24h"
        case .w1: return "1W"
        case .m1: return "1M"
        case .m6: return "6M"
        }
    }

    /// Short-range tabs show the ring; long ranges show a legend + bar chart (SPEC 3).
    public var usesRing: Bool {
        switch self {
        case .h6, .h12, .h24: return true
        default: return false
        }
    }

    /// Chart bucket for the range.
    public var bucket: Bucket {
        switch self {
        case .now, .h6: return .minutes(15)
        case .h12: return .minutes(30)
        case .h24: return .minutes(60)
        case .w1, .m1: return .day
        case .m6: return .week
        }
    }

    /// Number of buckets shown in the chart.
    public var bucketCount: Int {
        switch self {
        case .now, .h6, .h12, .h24: return 24
        case .w1: return 7
        case .m1: return 30
        case .m6: return 26
        }
    }

    /// Days in a rolling day-based window, including today (SPEC 3: 7, 30, 182).
    public var days: Int? {
        switch self {
        case .w1: return 7
        case .m1: return 30
        case .m6: return 182
        default: return nil
        }
    }

    /// Length of an hour-based window in seconds.
    public var hours: Int? {
        switch self {
        case .h6: return 6
        case .h12: return 12
        case .h24: return 24
        default: return nil
        }
    }

    public enum Bucket: Equatable, Sendable {
        case minutes(Int)
        case day
        case week

        public var unitLabel: String {
            switch self {
            case .minutes(60): return "hour"
            case .minutes(let m): return "\(m) min"
            case .day: return "day"
            case .week: return "week"
            }
        }
    }

    /// The window `[start, end)` for this tab ending at `now`, in the given calendar.
    /// Hour ranges are exact; day ranges start at local midnight `days - 1` days before today.
    public func window(endingAt now: Date, calendar: Calendar = .current) -> DateInterval? {
        if let hours {
            return DateInterval(start: now.addingTimeInterval(-Double(hours) * 3600), end: now)
        }
        if let days {
            let today = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return nil }
            return DateInterval(start: start, end: now)
        }
        return nil
    }
}

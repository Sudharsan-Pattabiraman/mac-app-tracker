import Foundation

/// The chart buckets for a tab ending at `now` (SPEC 3): start/end dates and labels.
public struct BucketLayout: Sendable {
    public struct Slot: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public let label: String
        public let axisLabel: String
    }

    public let tab: TimeTab
    public let slots: [Slot]

    /// Hour-based buckets align to the local clock (works for half-hour time zones);
    /// day and week buckets start at local midnight. The last bucket contains `now`.
    public init(tab: TimeTab, now: Date, calendar: Calendar) {
        self.tab = tab
        let count = tab.bucketCount
        var slots: [Slot] = []
        slots.reserveCapacity(count)

        switch tab.bucket {
        case .minutes(let minutes):
            let step = TimeInterval(minutes * 60)
            let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let minuteInHour = calendar.component(.minute, from: now)
            let lastStart = hourStart.addingTimeInterval(TimeInterval((minuteInHour / minutes) * minutes * 60))
            let time = Self.formatter("HH:mm", calendar)
            for i in 0..<count {
                let start = lastStart.addingTimeInterval(-step * TimeInterval(count - 1 - i))
                let label = time.string(from: start)
                slots.append(Slot(start: start, end: start.addingTimeInterval(step), label: label,
                                  axisLabel: i == count - 1 ? "now" : String(label.prefix(2))))
            }

        case .day:
            let today = calendar.startOfDay(for: now)
            let long = Self.formatter(tab == .w1 ? "EEE d" : "MMM d", calendar)
            let short = Self.formatter(tab == .w1 ? "EEE" : "MMM d", calendar)
            for i in 0..<count {
                let start = calendar.date(byAdding: .day, value: -(count - 1 - i), to: today) ?? today
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
                slots.append(Slot(start: start, end: end, label: long.string(from: start), axisLabel: short.string(from: start)))
            }

        case .week:
            // 26 weeks ending with the week that contains today, covering exactly the 182-day window.
            let today = calendar.startOfDay(for: now)
            let long = Self.formatter("MMM d", calendar)
            let short = Self.formatter("MMM", calendar)
            for i in 0..<count {
                let daysBack = 7 * (count - 1 - i) + 6
                let start = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
                slots.append(Slot(start: start, end: end, label: "Week of " + long.string(from: start),
                                  axisLabel: short.string(from: start)))
            }
        }
        self.slots = slots
    }

    /// Index of the slot containing `date`, if any.
    public func index(of date: Date) -> Int? {
        var low = 0
        var high = slots.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if date < slots[mid].start {
                high = mid - 1
            } else if date >= slots[mid].end {
                low = mid + 1
            } else {
                return mid
            }
        }
        return nil
    }

    static func formatter(_ pattern: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter
    }
}

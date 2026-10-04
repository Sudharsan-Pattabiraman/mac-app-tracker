import Foundation

/// Pure aggregation over recorded intervals. Callers clip intervals to the window first.
public enum Aggregator {
    public struct Totals: Equatable, Sendable {
        public var active: TimeInterval = 0
        public var idle: TimeInterval = 0
        public var away: TimeInterval = 0

        public init(active: TimeInterval = 0, idle: TimeInterval = 0, away: TimeInterval = 0) {
            self.active = active
            self.idle = idle
            self.away = away
        }

        public mutating func add(_ state: ActivityState, _ seconds: TimeInterval) {
            switch state {
            case .active: active += seconds
            case .idle: idle += seconds
            case .away: away += seconds
            }
        }
    }

    public static func clip(_ intervals: [TrackedInterval], to window: DateInterval) -> [TrackedInterval] {
        intervals.compactMap { $0.clipped(to: window) }
    }

    public static func totals(_ intervals: [TrackedInterval]) -> Totals {
        var totals = Totals()
        for interval in intervals { totals.add(interval.state, interval.duration) }
        return totals
    }

    /// Active time per app, most-used first (ties by name for a stable order).
    public static func activeByApp(_ intervals: [TrackedInterval]) -> [(app: AppIdentity, active: TimeInterval)] {
        var byApp: [AppIdentity: TimeInterval] = [:]
        for interval in intervals where interval.state == .active {
            guard let app = interval.app else { continue }
            byApp[app, default: 0] += interval.duration
        }
        return byApp.map { (app: $0.key, active: $0.value) }
            .sorted { $0.active != $1.active ? $0.active > $1.active : $0.app.name < $1.app.name }
    }

    /// Active time per domain for one app, most-used first.
    public static func activeByDomain(_ intervals: [TrackedInterval], app: AppIdentity) -> [DomainUsage] {
        var byDomain: [String: TimeInterval] = [:]
        for interval in intervals where interval.state == .active && interval.app == app {
            guard let domain = interval.domain else { continue }
            byDomain[domain, default: 0] += interval.duration
        }
        return byDomain.map { DomainUsage(domain: $0.key, active: $0.value) }
            .sorted { $0.active != $1.active ? $0.active > $1.active : $0.domain < $1.domain }
    }

    /// Active time distributed into the layout's buckets (optionally for one app only).
    public static func buckets(_ intervals: [TrackedInterval], layout: BucketLayout, app: AppIdentity? = nil) -> [UsageBucket] {
        var seconds = Array(repeating: 0.0, count: layout.slots.count)
        for interval in intervals where interval.state == .active {
            if let app, interval.app != app { continue }
            guard var index = layout.index(of: interval.start) ?? firstSlot(after: interval.start, in: layout) else { continue }
            while index < layout.slots.count {
                let slot = layout.slots[index]
                guard slot.start < interval.end else { break }
                let overlap = min(slot.end, interval.end).timeIntervalSince(max(slot.start, interval.start))
                if overlap > 0 { seconds[index] += overlap }
                index += 1
            }
        }
        return layout.slots.enumerated().map { index, slot in
            UsageBucket(index: index, start: slot.start, label: slot.label, axisLabel: slot.axisLabel, active: seconds[index])
        }
    }

    private static func firstSlot(after date: Date, in layout: BucketLayout) -> Int? {
        guard let first = layout.slots.first, date < first.start else { return nil }
        return 0
    }

    /// Sessions of one app (SPEC 5.5/5.6): active intervals of that app joined while no other app was
    /// active in between and any gap is shorter than `gap`. Input: active intervals of all apps.
    public static func sessions(_ intervals: [TrackedInterval], app: AppIdentity, gap: TimeInterval) -> [Session] {
        let active = intervals.filter { $0.state == .active }.sorted { $0.start < $1.start }
        var sessions: [Session] = []
        var current: Session?
        var otherAppSinceLast = false
        for interval in active {
            guard interval.app == app else {
                if current != nil { otherAppSinceLast = true }
                continue
            }
            if var session = current, !otherAppSinceLast, interval.start.timeIntervalSince(session.end) < gap {
                session.end = max(session.end, interval.end)
                session.active += interval.duration
                current = session
            } else {
                if let session = current { sessions.append(session) }
                current = Session(start: interval.start, end: interval.end, active: interval.duration)
            }
            otherAppSinceLast = false
        }
        if let session = current { sessions.append(session) }
        return sessions
    }

    public struct Session: Equatable, Sendable {
        public var start: Date
        public var end: Date
        /// Active time inside the session (excludes short idle gaps).
        public var active: TimeInterval
    }

    /// Recent stretches for the Now tab, newest first: app stretches (same rule as sessions) and
    /// Idle periods of at least `gap`. Away time is left out.
    public static func stretches(_ intervals: [TrackedInterval], gap: TimeInterval) -> [Stretch] {
        let sorted = intervals.filter { $0.state != .away }.sorted { $0.start < $1.start }
        var result: [Stretch] = []
        var appStretch: (app: AppIdentity, start: Date, end: Date, active: TimeInterval)?
        var idleRun: (start: Date, end: Date)?

        func flushIdle() {
            if let run = idleRun, run.end.timeIntervalSince(run.start) >= gap {
                result.append(Stretch(start: run.start, duration: run.end.timeIntervalSince(run.start), app: nil))
            }
            idleRun = nil
        }
        func flushApp() {
            if let s = appStretch {
                result.append(Stretch(start: s.start, duration: s.active, app: s.app))
            }
            appStretch = nil
        }

        for interval in sorted {
            if interval.state == .idle {
                if let run = idleRun, interval.start.timeIntervalSince(run.end) < 1 {
                    idleRun = (run.start, max(run.end, interval.end))
                } else {
                    flushIdle()
                    idleRun = (interval.start, interval.end)
                }
                continue
            }
            guard let app = interval.app else { continue }
            let gapLongEnough = idleRun.map { $0.end.timeIntervalSince($0.start) >= gap } ?? false
            if var s = appStretch, s.app == app, !gapLongEnough, interval.start.timeIntervalSince(s.end) < gap {
                s.end = max(s.end, interval.end)
                s.active += interval.duration
                appStretch = s
                idleRun = nil
            } else {
                flushApp()
                flushIdle()
                appStretch = (app, interval.start, interval.end, interval.duration)
            }
        }
        flushApp()
        flushIdle()
        return result.sorted { $0.start > $1.start }
    }
}

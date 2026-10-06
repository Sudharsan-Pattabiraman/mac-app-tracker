import Foundation

/// Turns a stream of `TrackerEvent`s into recorded intervals (SPEC 2).
///
/// Rules, in priority order, for what the current moment is:
/// 1. Paused → untracked.
/// 2. Any away reason (locked, asleep, display asleep, screensaver, other user) → Away.
/// 3. No frontmost app, or an excluded app → untracked.
/// 4. No input for `idleThreshold` and no display-sleep assertion → Idle,
///    backdated to the last input (or last assertion, whichever is later).
/// 5. Otherwise → Active, credited to the frontmost app (and domain).
///
/// Not thread-safe: drive it from one thread (the main thread in the app).
public final class TrackerEngine {
    public private(set) var config: TrackerConfig
    public private(set) var open: OpenSegment
    public private(set) var frontmost: AppIdentity?
    public private(set) var domain: String?

    /// The current stretch (SPEC 5.5): continuous activity in one app, broken by switching apps
    /// or by an Idle/Away gap of at least `config.stretchGap`.
    public private(set) var stretchApp: AppIdentity?
    public private(set) var stretchStart: Date?

    private let calendar: Calendar
    private var awayReasons: Set<AwayReason> = []
    private var paused = false
    private var isIdle = false
    private var lastInputAt: Date
    private var lastAssertionAt: Date?
    private var lastActiveEnd: Date?
    private var lastActiveApp: AppIdentity?

    public init(config: TrackerConfig, calendar: Calendar, now: Date, frontmost: AppIdentity?,
                awayReasons: Set<AwayReason> = [], paused: Bool = false) {
        self.config = config
        self.calendar = calendar
        self.frontmost = frontmost
        self.awayReasons = awayReasons
        self.paused = paused
        self.lastInputAt = now
        self.open = OpenSegment(start: now, state: nil, app: nil, domain: nil)
        let target = desiredSegment()
        self.open = OpenSegment(start: now, state: target.state, app: target.app, domain: target.domain)
        if target.state == .active {
            stretchApp = target.app
            stretchStart = now
        }
    }

    /// The state being recorded right now (nil while untracked).
    public var currentState: ActivityState? { open.state }

    /// The open segment as an interval ending at `now`, if it's tracked and non-empty.
    public func openInterval(until now: Date) -> TrackedInterval? {
        guard let state = open.state, now > open.start else { return nil }
        return TrackedInterval(start: open.start, end: now, state: state, app: open.app, domain: open.domain)
    }

    /// Applies one event and returns what to persist.
    @discardableResult
    public func handle(_ event: TrackerEvent, at time: Date) -> [TrackerOutput] {
        var outputs: [TrackerOutput] = []
        // Time never runs backwards inside the engine.
        let now = max(time, open.start)
        rollOverMidnight(upTo: now, into: &outputs)

        var boundary: Date?
        switch event {
        case .appActivated(let app):
            if app != frontmost { domain = nil }
            frontmost = app

        case .domainChanged(let newDomain):
            domain = newDomain

        case .inputSample(let secondsSinceInput, let assertion):
            guard awayReasons.isEmpty else { break }
            lastInputAt = max(lastInputAt, now.addingTimeInterval(-max(0, secondsSinceInput)))
            if assertion { lastAssertionAt = now }
            let lastSign = max(lastInputAt, lastAssertionAt ?? .distantPast)
            let nowIdle = !assertion && now.timeIntervalSince(lastSign) >= config.idleThreshold
            if nowIdle != isIdle {
                isIdle = nowIdle
                // Idle began at the last sign of life. Activity resumed at the latest input, or now
                // when no recent input explains it (a display-sleep assertion, e.g. a video, ended it).
                let resumedByInput = now.timeIntervalSince(lastInputAt) < config.idleThreshold
                boundary = nowIdle ? lastSign : (resumedByInput ? lastInputAt : now)
            }

        case .awayStarted(let reason):
            // The display slept, the screen locked, etc. after a quiet stretch: macOS usually does
            // that *because* nobody was using the Mac, so the quiet minutes were Idle, not Active.
            let lastSign = max(lastInputAt, lastAssertionAt ?? .distantPast)
            if awayReasons.isEmpty, !isIdle, open.state == .active,
               now.timeIntervalSince(lastSign) >= config.idleBeforeAway {
                isIdle = true
                transition(boundary: lastSign, now: now, into: &outputs)
            }
            awayReasons.insert(reason)

        case .awayEnded(let reason):
            let wasAway = !awayReasons.isEmpty
            awayReasons.remove(reason)
            if wasAway && awayReasons.isEmpty {
                // Coming back counts as activity until the next idle check says otherwise.
                isIdle = false
                lastInputAt = now
            }

        case .pausedChanged(let isPaused):
            paused = isPaused

        case .configChanged(let newConfig):
            config = newConfig

        case .tick:
            break
        }

        transition(boundary: boundary, now: now, into: &outputs)
        return outputs
    }

    // MARK: - State

    private func desiredSegment() -> (state: ActivityState?, app: AppIdentity?, domain: String?) {
        if paused { return (nil, nil, nil) }
        if !awayReasons.isEmpty { return (.away, nil, nil) }
        guard let app = frontmost, !config.excludedBundleIDs.contains(app.bundleID) else { return (nil, nil, nil) }
        if isIdle { return (.idle, nil, nil) }
        return (.active, app, domain)
    }

    private func transition(boundary: Date?, now: Date, into outputs: inout [TrackerOutput]) {
        let target = desiredSegment()
        guard target.state != open.state || target.app != open.app || target.domain != open.domain else { return }

        var split = now
        if let boundary {
            // Idle detected late: if it began before the current segment, earlier Active rows
            // (already recorded) must be turned into Idle too. Never reach back further than
            // the threshold plus a margin, so a bad sample can't rewrite history.
            if target.state == .idle, open.state == .active, boundary < open.start {
                let earliest = now.addingTimeInterval(-(config.idleThreshold + 120))
                let start = max(boundary, earliest)
                if start < open.start {
                    outputs.append(.reclassifyAsIdle(DateInterval(start: start, end: open.start)))
                }
            }
            split = min(max(boundary, open.start), now)
        }

        close(at: split, into: &outputs)
        let previousState = open.state
        let previousApp = open.app
        open = OpenSegment(start: split, state: target.state, app: target.app, domain: target.domain)
        updateStretch(previousState: previousState, previousApp: previousApp, at: split)
    }

    private func close(at end: Date, into outputs: inout [TrackerOutput]) {
        guard let state = open.state, end > open.start else { return }
        let interval = TrackedInterval(start: open.start, end: end, state: state, app: open.app, domain: open.domain)
        for piece in DaySplitter.split(interval, calendar: calendar) {
            outputs.append(.record(piece))
        }
    }

    private func updateStretch(previousState: ActivityState?, previousApp: AppIdentity?, at time: Date) {
        if previousState == .active {
            lastActiveEnd = time
            lastActiveApp = previousApp
        }
        guard open.state == .active, let app = open.app else { return }
        let continues = stretchApp == app
            && lastActiveApp == app
            && lastActiveEnd.map { time.timeIntervalSince($0) < config.stretchGap } == true
        if !continues {
            stretchApp = app
            stretchStart = time
        }
    }

    /// Records the open segment up to each midnight it has crossed, so no row spans two days.
    private func rollOverMidnight(upTo now: Date, into outputs: inout [TrackerOutput]) {
        var midnight = DaySplitter.nextMidnight(after: open.start, calendar: calendar)
        while midnight <= now {
            close(at: midnight, into: &outputs)
            open.start = midnight
            midnight = DaySplitter.nextMidnight(after: midnight, calendar: calendar)
        }
    }
}

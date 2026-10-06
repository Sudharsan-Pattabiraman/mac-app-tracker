import Foundation

/// Why the Mac counts as Away (SPEC 2.1). Several can be true at once (e.g. locked and display asleep).
public enum AwayReason: String, Hashable, Sendable, CaseIterable {
    case locked
    case systemSleep
    case displaySleep
    case screensaver
    case sessionInactive
}

/// Tracking settings the engine needs.
public struct TrackerConfig: Equatable, Sendable {
    /// No input (and no display-sleep assertion) for this long counts as Idle.
    public var idleThreshold: TimeInterval
    /// Apps that are never recorded.
    public var excludedBundleIDs: Set<String>
    /// A stretch/session ends on an Idle or Away gap of at least this long (SPEC 5.5).
    public var stretchGap: TimeInterval
    /// When Away starts (display sleep, lock, screensaver, sleep) after at least this long without
    /// input, that quiet stretch counts as Idle even if it was shorter than `idleThreshold` (SPEC 2.2).
    public var idleBeforeAway: TimeInterval

    public init(idleThreshold: TimeInterval = 5 * 60,
                excludedBundleIDs: Set<String> = [],
                stretchGap: TimeInterval = 2 * 60,
                idleBeforeAway: TimeInterval = 60) {
        self.idleThreshold = idleThreshold
        self.excludedBundleIDs = excludedBundleIDs
        self.stretchGap = stretchGap
        self.idleBeforeAway = idleBeforeAway
    }
}

/// Signals from macOS, already reduced to plain values by the platform layer.
public enum TrackerEvent: Equatable, Sendable {
    /// The frontmost app changed. `nil` when no regular app is frontmost.
    case appActivated(AppIdentity?)
    /// The frontmost browser's active tab changed (registrable domain, `DomainUsage.privateBrowsing`, or nil).
    case domainChanged(String?)
    /// Periodic idle check: seconds since the last keyboard/mouse/trackpad input, and whether
    /// the frontmost app currently prevents display sleep (video, calls).
    case inputSample(secondsSinceInput: TimeInterval, displaySleepAssertion: Bool)
    /// Send an `inputSample` just before this, so the engine knows when input last happened.
    case awayStarted(AwayReason)
    case awayEnded(AwayReason)
    case pausedChanged(Bool)
    case configChanged(TrackerConfig)
    /// Time passes (used to roll over midnight and keep live numbers fresh).
    case tick
}

/// A finished stretch of one state. Active intervals carry the app (and domain for browsers).
public struct TrackedInterval: Equatable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var state: ActivityState
    public var app: AppIdentity?
    public var domain: String?

    public init(start: Date, end: Date, state: ActivityState, app: AppIdentity? = nil, domain: String? = nil) {
        self.start = start
        self.end = end
        self.state = state
        self.app = state == .active ? app : nil
        self.domain = state == .active ? domain : nil
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// The part of this interval inside `window`, or nil if they don't overlap.
    public func clipped(to window: DateInterval) -> TrackedInterval? {
        let start = max(self.start, window.start)
        let end = min(self.end, window.end)
        guard end > start else { return nil }
        var copy = self
        copy.start = start
        copy.end = end
        return copy
    }
}

/// What the engine asks the store to do.
public enum TrackerOutput: Equatable, Sendable {
    /// Persist a finished interval (never crosses local midnight).
    case record(TrackedInterval)
    /// Idle detection reached back into already-recorded time: turn Active time in this range into Idle.
    case reclassifyAsIdle(DateInterval)
}

/// The interval currently in progress. `state == nil` means untracked (paused, excluded app, no app).
public struct OpenSegment: Equatable, Sendable {
    public var start: Date
    public let state: ActivityState?
    public let app: AppIdentity?
    public let domain: String?

    public init(start: Date, state: ActivityState?, app: AppIdentity?, domain: String?) {
        self.start = start
        self.state = state
        self.app = app
        self.domain = domain
    }
}

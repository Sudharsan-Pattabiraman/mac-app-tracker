import Foundation

/// The three tracked states (SPEC 2.1).
public enum ActivityState: Int, Codable, Sendable {
    case active = 0
    case idle = 1
    case away = 2
}

/// An app as TikTik identifies it.
public struct AppIdentity: Hashable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// One row of the app table: Active time in the range plus live RAM.
public struct AppUsage: Identifiable, Hashable, Sendable {
    public var id: String { app.bundleID }
    public let app: AppIdentity
    public let active: TimeInterval
    /// Current memory footprint; `nil` when the app isn't running.
    public var memoryBytes: UInt64?

    public init(app: AppIdentity, active: TimeInterval, memoryBytes: UInt64?) {
        self.app = app
        self.active = active
        self.memoryBytes = memoryBytes
    }
}

/// One chart bar.
public struct UsageBucket: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let start: Date
    /// Unique tooltip label, e.g. "09:00", "Mon 29", "Sep 14".
    public let label: String
    /// Short x-axis tick, e.g. "09", "Mon", "Apr".
    public let axisLabel: String
    public let active: TimeInterval

    public init(index: Int, start: Date, label: String, axisLabel: String? = nil, active: TimeInterval) {
        self.index = index
        self.start = start
        self.label = label
        self.axisLabel = axisLabel ?? label
        self.active = active
    }
}

/// Everything a range tab (6h … 6M) displays.
public struct RangeSummary: Sendable {
    public let tab: TimeTab
    public let window: DateInterval
    public let active: TimeInterval
    public let idle: TimeInterval
    public let away: TimeInterval
    public let buckets: [UsageBucket]
    public var apps: [AppUsage]
    /// Earliest recorded data, when it falls inside the window ("History starts Oct 1").
    public let historyStart: Date?

    public init(tab: TimeTab, window: DateInterval, active: TimeInterval, idle: TimeInterval,
                away: TimeInterval, buckets: [UsageBucket], apps: [AppUsage], historyStart: Date?) {
        self.tab = tab
        self.window = window
        self.active = active
        self.idle = idle
        self.away = away
        self.buckets = buckets
        self.apps = apps
        self.historyStart = historyStart
    }

    public var tracked: TimeInterval { active + idle + away }
    public var isEmpty: Bool { tracked < 1 }
}

/// A site's share of a browser's time (SPEC 2.5).
public struct DomainUsage: Identifiable, Hashable, Sendable {
    public var id: String { domain }
    /// Registrable domain, or `DomainUsage.privateBrowsing`.
    public let domain: String
    public let active: TimeInterval

    public static let privateBrowsing = "Private browsing"

    public init(domain: String, active: TimeInterval) {
        self.domain = domain
        self.active = active
    }
}

/// App detail page (SPEC 5.6).
public struct AppDetail: Sendable {
    public let app: AppIdentity
    public let tab: TimeTab
    public let active: TimeInterval
    public let shareOfActive: Double
    public let buckets: [UsageBucket]
    public let sessions: Int
    public let longestSession: TimeInterval
    public let firstUsed: Date?
    public let lastUsed: Date?
    public var memoryBytes: UInt64?
    /// `nil` for non-browser apps.
    public var domains: [DomainUsage]?
    /// True when the browser refused Automation access.
    public var domainAccessDenied: Bool

    public init(app: AppIdentity, tab: TimeTab, active: TimeInterval, shareOfActive: Double,
                buckets: [UsageBucket], sessions: Int, longestSession: TimeInterval,
                firstUsed: Date?, lastUsed: Date?, memoryBytes: UInt64?,
                domains: [DomainUsage]?, domainAccessDenied: Bool) {
        self.app = app
        self.tab = tab
        self.active = active
        self.shareOfActive = shareOfActive
        self.buckets = buckets
        self.sessions = sessions
        self.longestSession = longestSession
        self.firstUsed = firstUsed
        self.lastUsed = lastUsed
        self.memoryBytes = memoryBytes
        self.domains = domains
        self.domainAccessDenied = domainAccessDenied
    }
}

/// A finished or ongoing stretch for the Now tab's Recent list. `app == nil` means Idle.
public struct Stretch: Identifiable, Hashable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let duration: TimeInterval
    public let app: AppIdentity?

    public init(start: Date, duration: TimeInterval, app: AppIdentity?) {
        self.start = start
        self.duration = duration
        self.app = app
    }
}

/// The Now tab (SPEC 5.5).
public struct NowSnapshot: Sendable {
    public let app: AppIdentity?
    public let state: ActivityState
    /// When the current stretch (or idle period) began.
    public let since: Date
    public let site: String?
    public let siteSince: Date?
    public let todayInApp: TimeInterval
    public var memoryBytes: UInt64?
    public let recent: [Stretch]

    public init(app: AppIdentity?, state: ActivityState, since: Date, site: String?, siteSince: Date?,
                todayInApp: TimeInterval, memoryBytes: UInt64?, recent: [Stretch]) {
        self.app = app
        self.state = state
        self.since = since
        self.site = site
        self.siteSince = siteSince
        self.todayInApp = todayInApp
        self.memoryBytes = memoryBytes
        self.recent = recent
    }
}

import AppKit
import os
import TikTikCore
import TikTikStore

/// Owns the tracking engine, the database and the macOS monitors, and keeps them in sync.
@MainActor
final class Tracker {
    let calendar: Calendar = .autoupdatingCurrent
    let store: TrackerStore
    let queries: UsageQueries
    let memory = MemorySampler()
    let browser = BrowserMonitor()

    private(set) var engine: TrackerEngine
    /// When the current domain was first seen (Now tab "4m 10s on this site").
    private(set) var domainSince: Date?

    /// Fired when the recorded state, app or domain changes (menu bar, Now tab).
    var onLiveChange: (() -> Void)?
    /// Fired when stored data changed in a way visible views should reload for.
    var onDataChange: (() -> Void)?

    private let frontmost = FrontmostAppMonitor()
    private let session = SessionMonitor()
    private let input = InputIdleMonitor()
    private var checkpointTimer: Timer?
    private var lastMaintenanceDay: Int?
    private var isPaused = false
    private let log = Logger(subsystem: "app.tiktik", category: "tracker")

    init(store: TrackerStore, config: TrackerConfig, websiteTracking: Bool) {
        self.store = store
        self.queries = UsageQueries(store: store, calendar: .autoupdatingCurrent)
        let now = Date()
        let front = NSWorkspace.shared.frontmostApplication.flatMap { app in
            FrontmostAppMonitor.counts(app) ? FrontmostAppMonitor.identity(of: app) : nil
        }
        engine = TrackerEngine(config: config, calendar: .autoupdatingCurrent, now: now, frontmost: front,
                               awayReasons: SessionMonitor.isScreenLocked() ? [.locked] : [])
        browser.isEnabled = websiteTracking
        input.idleThreshold = config.idleThreshold
    }

    // MARK: Lifecycle

    func start() {
        do {
            if let recovered = try store.recoverOpenInterval(calendar: calendar) {
                // Only happens when the previous run didn't quit normally (crash, force quit, killed).
                log.notice("Previous run ended unexpectedly; recovered \(Int(recovered.duration)) s ending \(recovered.end, privacy: .public)")
            }
        } catch {
            log.error("Recovery failed: \(error.localizedDescription, privacy: .public)")
        }
        runDailyMaintenance(now: Date())

        frontmost.onChange = { [weak self] app in
            guard let self else { return }
            self.send(.appActivated(app))
            self.browser.frontmostChanged(to: app)
        }
        session.onChange = { [weak self] reason, started in
            guard let self else { return }
            self.log.notice("\(started ? "Away started" : "Away ended", privacy: .public): \(reason.rawValue, privacy: .public)")
            self.send(started ? .awayStarted(reason) : .awayEnded(reason))
            if !started { self.input.sampleNow() }
        }
        input.frontmostPID = { [weak self] in self?.frontmost.currentPID }
        input.onSample = { [weak self] seconds, assertion in
            self?.send(.inputSample(secondsSinceInput: seconds, displaySleepAssertion: assertion))
        }
        browser.onDomain = { [weak self] domain in
            self?.send(.domainChanged(domain))
        }

        frontmost.start()
        session.start()
        input.start()

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.minuteTick()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        checkpointTimer = timer
    }

    /// Records everything up to now (app quitting).
    func shutdown() {
        let now = Date()
        send(.tick, at: now)
        if let open = engine.openInterval(until: now) {
            persist([.record(open)])
        }
        do { try store.checkpoint(nil) } catch { log.error("Final checkpoint failed") }
        log.notice("Tracking stopped, data saved")
    }

    // MARK: Inputs from the app

    func setPaused(_ paused: Bool) {
        isPaused = paused
        send(.pausedChanged(paused))
    }

    /// Settings → Clear all data. Also drops the interval in progress, so nothing from before
    /// the clear is saved afterwards; tracking carries on from now.
    func deleteAllData() throws {
        let now = Date()
        engine.handle(.pausedChanged(true), at: now)   // closes the open interval; its output is discarded
        defer {
            if !isPaused { engine.handle(.pausedChanged(false), at: now) }
            domainSince = engine.open.domain == nil ? nil : now
            onLiveChange?()
        }
        try store.deleteAll()
    }

    func apply(config: TrackerConfig, websiteTracking: Bool) {
        input.idleThreshold = config.idleThreshold
        if config != engine.config { send(.configChanged(config)) }
        if browser.isEnabled != websiteTracking {
            browser.isEnabled = websiteTracking
            if websiteTracking { browser.frontmostChanged(to: frontmost.current) }
        }
    }

    /// The interval in progress, up to now (not yet in the database).
    func liveInterval(now: Date = Date()) -> TrackedInterval? {
        engine.openInterval(until: now)
    }

    // MARK: Internals

    private func send(_ event: TrackerEvent, at time: Date = Date()) {
        let before = engine.open
        let outputs = engine.handle(event, at: time)
        if !outputs.isEmpty { persist(outputs) }
        let after = engine.open
        if after.domain != before.domain || after.app != before.app {
            domainSince = after.domain == nil ? nil : after.start
        }
        if after.state != before.state || after.app != before.app || after.domain != before.domain {
            onLiveChange?()
        }
    }

    private func persist(_ outputs: [TrackerOutput]) {
        do {
            var pending: [TrackedInterval] = []
            for output in outputs {
                switch output {
                case .record(let interval):
                    pending.append(interval)
                case .reclassifyAsIdle(let range):
                    // Rows must exist before they can be reclassified.
                    try store.append(pending, calendar: calendar)
                    pending.removeAll()
                    try store.reclassifyAsIdle(range)
                }
            }
            try store.append(pending, calendar: calendar)
        } catch {
            log.error("Saving intervals failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func minuteTick() {
        let now = Date()
        send(.tick, at: now)
        do {
            try store.checkpoint(engine.openInterval(until: now))
        } catch {
            log.error("Checkpoint failed: \(error.localizedDescription, privacy: .public)")
        }
        runDailyMaintenance(now: now)
        browser.refreshAccess()
        onDataChange?()
    }

    /// Retention runs at launch and on the first tick of each new day (SPEC 4).
    private func runDailyMaintenance(now: Date) {
        let today = DaySplitter.dayKey(now, calendar: calendar)
        guard today != lastMaintenanceDay else { return }
        lastMaintenanceDay = today
        do {
            let deleted = try store.applyRetention(now: now, calendar: calendar)
            if deleted > 0 { log.info("Retention removed \(deleted) old rows") }
        } catch {
            log.error("Retention failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

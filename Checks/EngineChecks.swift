import Foundation
import TikTikCore

/// Scripted timelines for TrackerEngine and DaySplitter.
func engineChecks(_ h: inout Harness) {
    let cal = Calendars.kolkata
    let xcode = AppIdentity(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
    let vault = AppIdentity(bundleID: "com.1password.1password", name: "1Password")
    func at(_ hh: Int, _ mm: Int, _ ss: Int = 0, day: Int = 3) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hh, minute: mm, second: ss))!
    }
    func records(_ outputs: [TrackerOutput]) -> [TrackedInterval] {
        outputs.compactMap { if case .record(let i) = $0 { return i } else { return nil } }
    }

    h.group("engine: app switches") { h in
        let e = TrackerEngine(config: TrackerConfig(), calendar: cal, now: at(10, 0), frontmost: xcode)
        h.equal(e.currentState, .active, "starts active")
        let out = e.handle(.appActivated(chrome), at: at(10, 10))
        h.equal(records(out), [TrackedInterval(start: at(10, 0), end: at(10, 10), state: .active, app: xcode)], "Xcode recorded")
        h.equal(e.open.app, chrome, "Chrome open")
        h.equal(e.handle(.tick, at: at(10, 20)), [], "tick records nothing")
        h.equal(e.openInterval(until: at(10, 20))?.duration, 600, "open interval runs to now")
    }

    h.group("engine: idle is backdated to the last input") { h in
        let e = TrackerEngine(config: TrackerConfig(idleThreshold: 300), calendar: cal, now: at(10, 0), frontmost: xcode)
        h.equal(e.handle(.inputSample(secondsSinceInput: 0, displaySleepAssertion: false), at: at(10, 3)), [], "active input")
        h.equal(e.handle(.inputSample(secondsSinceInput: 240, displaySleepAssertion: false), at: at(10, 7)), [], "4 min quiet is not idle")
        let out = e.handle(.inputSample(secondsSinceInput: 305, displaySleepAssertion: false), at: at(10, 8, 5))
        h.equal(records(out), [TrackedInterval(start: at(10, 0), end: at(10, 3), state: .active, app: xcode)], "active ends at last input")
        h.equal(e.open.state, .idle, "now idle")
        h.equal(e.open.start, at(10, 3), "idle starts at last input")

        let back = e.handle(.inputSample(secondsSinceInput: 2, displaySleepAssertion: false), at: at(10, 20))
        h.equal(records(back), [TrackedInterval(start: at(10, 3), end: at(10, 19, 58), state: .idle)], "idle ends at first new input")
        h.equal(e.open.state, .active, "active again")
        h.equal(e.open.app, xcode, "still Xcode")
    }

    h.group("engine: display-sleep assertion keeps time active") { h in
        let e = TrackerEngine(config: TrackerConfig(idleThreshold: 300), calendar: cal, now: at(20, 0), frontmost: chrome)
        h.equal(e.handle(.inputSample(secondsSinceInput: 900, displaySleepAssertion: true), at: at(20, 15)), [], "video playing: still active")
        h.equal(e.open.state, .active)
        h.equal(e.handle(.inputSample(secondsSinceInput: 1_500, displaySleepAssertion: true), at: at(20, 25)), [], "still playing")
        // Video stops; 5 min later TikTik notices.
        let out = e.handle(.inputSample(secondsSinceInput: 1_800, displaySleepAssertion: false), at: at(20, 30))
        h.equal(records(out), [TrackedInterval(start: at(20, 0), end: at(20, 25), state: .active, app: chrome)],
                "active until the assertion was last seen")
        h.equal(e.open.start, at(20, 25), "idle from the last assertion")

        // A video starts while idle: active from now, not from the old input.
        let resumed = e.handle(.inputSample(secondsSinceInput: 2_400, displaySleepAssertion: true), at: at(20, 40))
        h.equal(records(resumed), [TrackedInterval(start: at(20, 25), end: at(20, 40), state: .idle)], "idle until the video started")
        h.equal(e.open.state, .active)
    }

    h.group("engine: away with overlapping reasons") { h in
        let e = TrackerEngine(config: TrackerConfig(), calendar: cal, now: at(11, 0), frontmost: xcode)
        e.handle(.inputSample(secondsSinceInput: 0, displaySleepAssertion: false), at: at(11, 30))
        let lock = e.handle(.awayStarted(.locked), at: at(11, 30))
        h.equal(records(lock), [TrackedInterval(start: at(11, 0), end: at(11, 30), state: .active, app: xcode)])
        h.equal(e.open.state, .away)
        h.equal(e.handle(.awayStarted(.displaySleep), at: at(11, 31)), [], "second reason changes nothing")
        h.equal(e.handle(.awayEnded(.locked), at: at(12, 0)), [], "still away while display sleeps")
        let wake = e.handle(.awayEnded(.displaySleep), at: at(12, 1))
        h.equal(records(wake), [TrackedInterval(start: at(11, 30), end: at(12, 1), state: .away)], "away until the last reason ends")
        h.equal(e.open.state, .active)
        h.equal(e.handle(.inputSample(secondsSinceInput: 3_600, displaySleepAssertion: false), at: at(12, 1, 5)), [],
                "stale input after wake doesn't backdate into away")
        let idle = e.handle(.inputSample(secondsSinceInput: 3_900, displaySleepAssertion: false), at: at(12, 6, 5))
        h.equal(records(idle), [], "no input since wake: the active stretch is empty")
        h.equal(e.open.state, .idle)
        h.equal(e.open.start, at(12, 1), "idle from the wake")
    }

    h.group("engine: quiet time before Away is Idle") { h in
        // Display turns off 2 min after the last input (default on battery), before the 5 min threshold.
        let e = TrackerEngine(config: TrackerConfig(idleThreshold: 300), calendar: cal, now: at(9, 0), frontmost: xcode)
        e.handle(.inputSample(secondsSinceInput: 120, displaySleepAssertion: false), at: at(9, 12))
        let out = e.handle(.awayStarted(.displaySleep), at: at(9, 12))
        h.equal(records(out), [
            TrackedInterval(start: at(9, 0), end: at(9, 10), state: .active, app: xcode),
            TrackedInterval(start: at(9, 10), end: at(9, 12), state: .idle),
        ], "the 2 quiet minutes are idle")
        h.equal(e.open.state, .away)
        let back = e.handle(.awayEnded(.displaySleep), at: at(9, 30))
        h.equal(records(back), [TrackedInterval(start: at(9, 12), end: at(9, 30), state: .away)])
        h.equal(e.open.state, .active, "active again after wake")

        // Locking right after typing: no idle.
        let quick = TrackerEngine(config: TrackerConfig(idleThreshold: 300), calendar: cal, now: at(9, 0), frontmost: xcode)
        quick.handle(.inputSample(secondsSinceInput: 5, displaySleepAssertion: false), at: at(9, 10))
        h.equal(records(quick.handle(.awayStarted(.locked), at: at(9, 10))),
                [TrackedInterval(start: at(9, 0), end: at(9, 10), state: .active, app: xcode)], "manual lock stays active")

        // Watching a video, then locking: the video kept it active.
        let video = TrackerEngine(config: TrackerConfig(idleThreshold: 300), calendar: cal, now: at(9, 0), frontmost: chrome)
        video.handle(.inputSample(secondsSinceInput: 240, displaySleepAssertion: true), at: at(9, 10))
        h.equal(records(video.handle(.awayStarted(.locked), at: at(9, 10))),
                [TrackedInterval(start: at(9, 0), end: at(9, 10), state: .active, app: chrome)], "video then lock stays active")

        // Already idle when the display sleeps: idle continues until Away, nothing doubled.
        let idle = TrackerEngine(config: TrackerConfig(idleThreshold: 300), calendar: cal, now: at(9, 0), frontmost: xcode)
        idle.handle(.inputSample(secondsSinceInput: 360, displaySleepAssertion: false), at: at(9, 10))
        h.equal(records(idle.handle(.awayStarted(.displaySleep), at: at(9, 15))),
                [TrackedInterval(start: at(9, 4), end: at(9, 15), state: .idle)], "idle 9:04–9:15, then away")
    }

    h.group("engine: midnight") { h in
        let e = TrackerEngine(config: TrackerConfig(), calendar: cal, now: at(23, 30), frontmost: xcode)
        let tick = e.handle(.tick, at: at(0, 45, day: 4))
        h.equal(records(tick), [TrackedInterval(start: at(23, 30), end: at(0, 0, day: 4), state: .active, app: xcode)], "split at midnight")
        h.equal(e.open.start, at(0, 0, day: 4))
        let out = e.handle(.appActivated(chrome), at: at(0, 50, day: 4))
        h.equal(records(out), [TrackedInterval(start: at(0, 0, day: 4), end: at(0, 50, day: 4), state: .active, app: xcode)])

        let sleeper = TrackerEngine(config: TrackerConfig(), calendar: cal, now: at(22, 0), frontmost: xcode)
        sleeper.handle(.awayStarted(.systemSleep), at: at(23, 0))
        let wake = sleeper.handle(.awayEnded(.systemSleep), at: at(7, 0, day: 4))
        h.equal(records(wake), [
            TrackedInterval(start: at(23, 0), end: at(0, 0, day: 4), state: .away),
            TrackedInterval(start: at(0, 0, day: 4), end: at(7, 0, day: 4), state: .away),
        ], "overnight sleep is split per day")
    }

    h.group("engine: pause and excluded apps are untracked") { h in
        let e = TrackerEngine(config: TrackerConfig(excludedBundleIDs: [vault.bundleID]), calendar: cal, now: at(12, 0), frontmost: xcode)
        h.equal(records(e.handle(.pausedChanged(true), at: at(12, 10))).count, 1, "active recorded at pause")
        h.equal(e.open.state, nil, "paused is untracked")
        h.equal(e.handle(.appActivated(chrome), at: at(12, 20)), [], "switching while paused records nothing")
        h.equal(e.handle(.pausedChanged(false), at: at(12, 30)), [], "resuming records nothing")
        h.equal(e.open, OpenSegment(start: at(12, 30), state: .active, app: chrome, domain: nil))

        h.equal(records(e.handle(.appActivated(vault), at: at(13, 0))).count, 1)
        h.equal(e.open.state, nil, "excluded app untracked")
        h.equal(e.handle(.appActivated(xcode), at: at(13, 5)), [], "nothing recorded for the excluded app")
        h.equal(e.handle(.appActivated(nil), at: at(13, 10)).count, 1, "no frontmost app ends the interval")
        h.equal(e.open.state, nil)
    }

    h.group("engine: late idle reclassifies earlier rows") { h in
        let e = TrackerEngine(config: TrackerConfig(idleThreshold: 300), calendar: cal, now: at(9, 50), frontmost: xcode)
        e.handle(.inputSample(secondsSinceInput: 0, displaySleepAssertion: false), at: at(10, 0))
        // Chrome comes to the front by itself (no input) at 10:02.
        let switched = e.handle(.appActivated(chrome), at: at(10, 2))
        h.equal(records(switched), [TrackedInterval(start: at(9, 50), end: at(10, 2), state: .active, app: xcode)])
        let out = e.handle(.inputSample(secondsSinceInput: 330, displaySleepAssertion: false), at: at(10, 5, 30))
        h.equal(out, [.reclassifyAsIdle(DateInterval(start: at(10, 0), end: at(10, 2)))], "Xcode's last 2 min become idle")
        h.equal(e.open, OpenSegment(start: at(10, 2), state: .idle, app: nil, domain: nil))
    }

    h.group("engine: domains") { h in
        let e = TrackerEngine(config: TrackerConfig(), calendar: cal, now: at(10, 0), frontmost: chrome)
        h.equal(records(e.handle(.domainChanged("github.com"), at: at(10, 0, 3))).count, 1, "3 s without a domain")
        let out = e.handle(.domainChanged("google.com"), at: at(10, 5))
        h.equal(records(out), [TrackedInterval(start: at(10, 0, 3), end: at(10, 5), state: .active, app: chrome, domain: "github.com")])
        h.equal(e.open.domain, "google.com")
        e.handle(.appActivated(xcode), at: at(10, 6))
        h.equal(e.domain, nil, "domain clears on app switch")
        h.expect(TrackedInterval(start: at(1, 0), end: at(2, 0), state: .idle, app: chrome, domain: "x").app == nil,
                 "only active intervals carry an app")
    }

    h.group("engine: stretches") { h in
        let e = TrackerEngine(config: TrackerConfig(idleThreshold: 60), calendar: cal, now: at(10, 0), frontmost: xcode)
        e.handle(.domainChanged(nil), at: at(10, 1))
        e.handle(.inputSample(secondsSinceInput: 70, displaySleepAssertion: false), at: at(10, 11))   // idle from 10:09:50
        e.handle(.inputSample(secondsSinceInput: 1, displaySleepAssertion: false), at: at(10, 11, 31)) // back after 100 s
        h.equal(e.stretchStart, at(10, 0), "a gap under 2 min continues the stretch")
        e.handle(.awayStarted(.locked), at: at(10, 20))
        e.handle(.awayEnded(.locked), at: at(10, 25))
        h.equal(e.stretchStart, at(10, 25), "a 5 min gap starts a new stretch")
        e.handle(.appActivated(chrome), at: at(10, 30))
        e.handle(.appActivated(xcode), at: at(10, 30, 20))
        h.equal(e.stretchStart, at(10, 30, 20), "switching apps starts a new stretch")
        h.equal(e.stretchApp, xcode)
    }

    h.group("engine: config changes apply immediately") { h in
        let e = TrackerEngine(config: TrackerConfig(), calendar: cal, now: at(10, 0), frontmost: xcode)
        e.handle(.configChanged(TrackerConfig(excludedBundleIDs: [xcode.bundleID])), at: at(10, 5))
        h.equal(e.open.state, nil, "excluding the frontmost app stops recording it")
    }

    h.group("DaySplitter") { h in
        h.equal(DaySplitter.dayKey(at(23, 59), calendar: cal), 20261003)
        h.equal(DaySplitter.dayKey(at(0, 0, day: 4), calendar: cal), 20261004)
        h.equal(DaySplitter.date(fromDayKey: 20261004, calendar: cal), at(0, 0, day: 4))
        let span = TrackedInterval(start: at(22, 0), end: at(1, 0, day: 5), state: .away)
        h.equal(DaySplitter.split(span, calendar: cal).map(\.duration), [7_200, 86_400, 3_600], "three days")

        // London's spring-forward day has 23 hours.
        let london = Calendars.london
        let start = london.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let day = TrackedInterval(start: start, end: start.addingTimeInterval(30 * 3600), state: .idle)
        h.equal(DaySplitter.split(day, calendar: london).map(\.duration), [23 * 3600, 7 * 3600], "DST day is 23 h")
    }
}

enum Calendars {
    static func make(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static let kolkata = make("Asia/Kolkata")
    static let london = make("Europe/London")
}

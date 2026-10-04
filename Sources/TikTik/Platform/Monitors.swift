import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import TikTikCore

/// Reports the frontmost app (SPEC 2.3). TikTik itself is ignored, so opening its own windows
/// never changes what's being tracked.
@MainActor
final class FrontmostAppMonitor {
    var onChange: ((AppIdentity?) -> Void)?
    private(set) var current: AppIdentity?
    private(set) var currentPID: pid_t?
    private var observer: NSObjectProtocol?

    static let ownBundleID = Bundle.main.bundleIdentifier ?? "app.tiktik"

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.update(app)
            }
        }
        update(NSWorkspace.shared.frontmostApplication)
    }

    private func update(_ running: NSRunningApplication?) {
        guard let running, running.bundleIdentifier != Self.ownBundleID else { return }
        current = Self.identity(of: running)
        currentPID = running.processIdentifier
        onChange?(current)
    }

    static func identity(of app: NSRunningApplication) -> AppIdentity? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? bundleID
        return AppIdentity(bundleID: bundleID, name: name)
    }
}

/// Lock, sleep, display sleep, screensaver and fast-user-switching (SPEC 2.1 Away).
@MainActor
final class SessionMonitor {
    var onChange: ((AwayReason, _ started: Bool) -> Void)?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .systemSleep, started: true)
        observe(workspace, NSWorkspace.didWakeNotification, .systemSleep, started: false)
        observe(workspace, NSWorkspace.screensDidSleepNotification, .displaySleep, started: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, .displaySleep, started: false)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, started: true)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, started: false)

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .locked, started: true)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), .locked, started: false)
        observe(distributed, Notification.Name("com.apple.screensaver.didstart"), .screensaver, started: true)
        observe(distributed, Notification.Name("com.apple.screensaver.didstop"), .screensaver, started: false)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ reason: AwayReason, started: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?(reason, started)
            }
        }
        tokens.append((center, token))
    }

    /// Whether the screen is locked right now (used at launch).
    static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool { return locked }
        if let locked = session["CGSSessionScreenIsLocked"] as? Int { return locked != 0 }
        return false
    }
}

/// Adaptive idle checks (SPEC 2.3): sleeps until the idle threshold could be reached, then
/// checks every 5 s. Display-sleep assertions are only checked once input has gone quiet.
@MainActor
final class InputIdleMonitor {
    var idleThreshold: TimeInterval = 300
    /// (seconds since last input, frontmost app prevents display sleep)
    var onSample: ((TimeInterval, Bool) -> Void)?
    /// PID of the app whose assertions count (the frontmost app).
    var frontmostPID: () -> pid_t? = { nil }

    private var timer: Timer?

    func start() {
        schedule(after: 5)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Check now (e.g. right after waking) and reschedule.
    func sampleNow() {
        timer?.invalidate()
        fire()
    }

    private func fire() {
        let seconds = Self.secondsSinceLastInput()
        let quietEnough = seconds >= idleThreshold - 10
        let assertion = quietEnough ? (frontmostPID().map(PowerAssertionProbe.preventsDisplaySleep(appPID:)) ?? false) : false
        onSample?(seconds, assertion)

        let next: TimeInterval
        if assertion {
            next = 15                                      // watching/listening: check less often
        } else if seconds < idleThreshold - 10 {
            next = min(60, idleThreshold - seconds - 5)    // active: wake just before idle is possible
        } else {
            next = 5                                       // idle or about to be: notice return quickly
        }
        schedule(after: max(5, next))
    }

    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fire()
            }
        }
        timer.tolerance = min(2, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this login session.
    static func secondsSinceLastInput() -> TimeInterval {
        if let anyInput = CGEventType(rawValue: UInt32.max) {   // kCGAnyInputEventType
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        }
        // Fallback: the most recent of the individual input event types.
        let types: [CGEventType] = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
                                    .otherMouseDown, .leftMouseDragged, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
}

/// Display-sleep power assertions (videos, calls) held by an app or its helper processes.
enum PowerAssertionProbe {
    private static let displaySleepTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

    static func preventsDisplaySleep(appPID: pid_t) -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == 0,   // kIOReturnSuccess
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: Any]
        else { return false }

        for (pidNumber, value) in byProcess {
            let pid = pid_t(truncatingIfNeeded: pidNumber.intValue)
            guard let assertions = value as? [[String: Any]],
                  assertions.contains(where: { displaySleepTypes.contains($0["AssertType"] as? String ?? "") })
            else { continue }
            if pid == appPID || ProcessTree.owner(of: pid, in: [appPID: true]) == true {
                return true
            }
        }
        return false
    }
}

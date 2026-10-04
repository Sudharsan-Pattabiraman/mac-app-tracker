import AppKit
import CoreServices
import os
import TikTikCore

/// Domain tracking for Chromium browsers (SPEC 2.5): while a supported browser is frontmost,
/// reads its active tab's URL every 5 s via AppleScript and reduces it to a registrable domain.
@MainActor
final class BrowserMonitor {
    /// Supported browsers (one shared Chromium AppleScript dictionary).
    static let browsers: [(bundleID: String, name: String)] = [
        ("com.google.Chrome", "Chrome"),
        ("com.google.Chrome.beta", "Chrome Beta"),
        ("com.google.Chrome.canary", "Chrome Canary"),
        ("org.chromium.Chromium", "Chromium"),
        ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Edge"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
    ]

    static func isSupported(_ bundleID: String) -> Bool {
        browsers.contains { $0.bundleID == bundleID }
    }

    enum Access: Equatable {
        case allowed, denied, notDetermined, notRunning
    }

    /// Called with the new domain (or nil) whenever it changes.
    var onDomain: ((String?) -> Void)?
    /// Called when a browser's access status changes (for the detail page and Settings).
    var onAccessChange: (() -> Void)?
    var isEnabled = true {
        didSet { if !isEnabled { stopProbing(clear: true) } }
    }

    private(set) var access: [String: Access] = [:]
    private var activeBrowser: String?
    private var timer: Timer?
    private var lastDomain: String?
    private var scripts: [String: NSAppleScript] = [:]
    private var permissionCheckInFlight: Set<String> = []
    private let suffixList: PublicSuffixList?
    private let log = Logger(subsystem: "app.tiktik", category: "browser")

    init() {
        if let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            suffixList = PublicSuffixList(contents: contents)
        } else {
            suffixList = nil
        }
    }

    func isDenied(_ bundleID: String) -> Bool {
        access[bundleID] == .denied
    }

    /// Call whenever the frontmost app changes.
    func frontmostChanged(to app: AppIdentity?) {
        guard isEnabled, let bundleID = app?.bundleID, Self.isSupported(bundleID) else {
            stopProbing(clear: activeBrowser != nil)
            return
        }
        guard bundleID != activeBrowser else { return }
        stopProbing(clear: false)
        activeBrowser = bundleID
        lastDomain = nil
        ensurePermission(for: bundleID, ask: true)
        probe()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.probe()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopProbing(clear: Bool) {
        timer?.invalidate()
        timer = nil
        activeBrowser = nil
        if clear, lastDomain != nil {
            lastDomain = nil
            onDomain?(nil)
        }
    }

    // MARK: Probing

    private func probe() {
        guard let bundleID = activeBrowser, access[bundleID] == .allowed else { return }
        switch Self.readActiveTab(bundleID: bundleID, scripts: &scripts) {
        case .tab(let url, let incognito):
            let domain = incognito ? DomainUsage.privateBrowsing : suffixList?.registrableDomain(forURL: url)
            publish(domain)
        case .noWindow:
            publish(nil)
        case .denied:
            setAccess(.denied, for: bundleID)
            publish(nil)
        case .failed:
            break   // keep the last known domain; try again in 5 s
        }
    }

    private func publish(_ domain: String?) {
        guard domain != lastDomain else { return }
        lastDomain = domain
        onDomain?(domain)
    }

    private enum TabResult {
        case tab(url: String, incognito: Bool)
        case noWindow
        case denied
        case failed
    }

    /// Runs the (cached, compiled) AppleScript. On the main thread, as NSAppleScript requires;
    /// a 1-second AppleEvent timeout bounds the worst case.
    private static func readActiveTab(bundleID: String, scripts: inout [String: NSAppleScript]) -> TabResult {
        let script: NSAppleScript
        if let cached = scripts[bundleID] {
            script = cached
        } else {
            let source = """
                with timeout of 1 second
                    tell application id "\(bundleID)"
                        if (count of windows) is 0 then return "TIKTIK:NOWINDOW"
                        set frontWindow to front window
                        return (mode of frontWindow) & linefeed & (URL of active tab of frontWindow)
                    end tell
                end timeout
                """
            guard let compiled = NSAppleScript(source: source) else { return .failed }
            var compileError: NSDictionary?
            guard compiled.compileAndReturnError(&compileError) else { return .failed }
            scripts[bundleID] = compiled
            script = compiled
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            return code == -1743 ? .denied : .failed
        }
        guard let text = result.stringValue else { return .failed }
        if text == "TIKTIK:NOWINDOW" { return .noWindow }
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2 else { return .failed }
        return .tab(url: String(lines[1]), incognito: lines[0] == "incognito")
    }

    // MARK: Permission

    /// Checks (and optionally asks for) Automation permission without blocking the main thread.
    func ensurePermission(for bundleID: String, ask: Bool) {
        guard !permissionCheckInFlight.contains(bundleID) else { return }
        permissionCheckInFlight.insert(bundleID)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = BrowserMonitor.automationStatus(bundleID: bundleID, ask: ask)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.permissionCheckInFlight.remove(bundleID)
                    self.setAccess(status, for: bundleID)
                    if status == .allowed, self.activeBrowser == bundleID { self.probe() }
                }
            }
        }
    }

    /// Asks every running supported browser for access (welcome screen, Settings).
    func requestAccessForRunningBrowsers() {
        for (bundleID, _) in Self.browsers where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            ensurePermission(for: bundleID, ask: true)
        }
    }

    /// Refreshes statuses without prompting.
    func refreshAccess() {
        for (bundleID, _) in Self.browsers where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            ensurePermission(for: bundleID, ask: false)
        }
    }

    /// "Chrome ✓ · Brave ✗" for installed browsers.
    func accessSummary() -> String {
        let installed = Self.browsers.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
        guard !installed.isEmpty else { return "No supported browser installed" }
        return installed.map { browser in
            let mark: String
            switch access[browser.bundleID] {
            case .allowed: mark = "✓"
            case .denied: mark = "✗"
            default: mark = "—"
            }
            return "\(browser.name) \(mark)"
        }.joined(separator: " · ")
    }

    private func setAccess(_ status: Access, for bundleID: String) {
        // "Not running" tells us nothing new about permission; keep what we knew.
        guard status != .notRunning, access[bundleID] != status else { return }
        access[bundleID] = status
        log.info("Automation access for \(bundleID, privacy: .public): \(String(describing: status), privacy: .public)")
        onAccessChange?()
    }

    nonisolated static func automationStatus(bundleID: String, ask: Bool) -> Access {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let descriptor = target.aeDesc else { return .notDetermined }
        let wildcard: FourCharCode = 0x2A2A_2A2A   // typeWildCard '****'
        let status = AEDeterminePermissionToAutomateTarget(descriptor, wildcard, wildcard, ask)
        switch status {
        case 0: return .allowed                    // noErr
        case -1743: return .denied                 // errAEEventNotPermitted
        case -1744: return .notDetermined          // errAEEventWouldRequireUserConsent
        case -600: return .notRunning              // procNotFound
        default: return .notDetermined
        }
    }
}

import AppKit
import Foundation

/// Live memory per app (SPEC 2.7): each app's footprint plus its helper processes.
/// Runs only while the popover is open; the measuring happens off the main thread.
@MainActor
final class MemorySampler {
    /// Bundle ID → bytes, from the latest sample.
    private(set) var footprints: [String: UInt64] = [:]
    var onUpdate: (() -> Void)?

    private var timer: Timer?
    private var isMeasuring = false

    func start() {
        sampleNow()
        timer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleNow()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func bytes(for bundleID: String) -> UInt64? {
        footprints[bundleID]
    }

    func sampleNow() {
        guard !isMeasuring else { return }
        isMeasuring = true
        var apps: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, app.processIdentifier > 0 else { continue }
            apps[app.processIdentifier] = bundleID
        }
        let snapshot = apps
        Task.detached(priority: .utility) { [weak self] in
            let totals = MemorySampler.measure(apps: snapshot)
            await MainActor.run {
                guard let self else { return }
                self.footprints = totals
                self.isMeasuring = false
                self.onUpdate?()
            }
        }
    }

    /// Sums every process's footprint into the app that owns it.
    nonisolated static func measure(apps: [pid_t: String]) -> [String: UInt64] {
        var totals: [String: UInt64] = [:]
        for pid in ProcessTree.allPIDs() {
            guard let bytes = ProcessTree.footprint(of: pid),
                  let bundleID = ProcessTree.owner(of: pid, in: apps) else { continue }
            totals[bundleID, default: 0] += bytes
        }
        return totals
    }
}

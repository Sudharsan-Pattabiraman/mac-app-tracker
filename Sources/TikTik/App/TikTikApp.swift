import AppKit
import Foundation
import os
import TikTikCore
import TikTikStore

/// Entry point. TikTik is a menu-bar-only app (LSUIElement), so it runs an
/// NSApplication with the accessory activation policy and no main window.
@main
@MainActor
enum TikTikMain {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            exit(DumpCommand.run())
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly; keep ours alive for the app's lifetime.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private let log = Logger(subsystem: "app.tiktik", category: "lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log.notice("TikTik \(version, privacy: .public) launched, pid \(ProcessInfo.processInfo.processIdentifier)")
        Fonts.registerBundledFonts()
        let sampleMode = CommandLine.arguments.contains("--sample-data")
        controller = AppController(sampleMode: sampleMode)
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.notice("TikTik quitting normally")
        // Save the interval in progress so nothing is lost on quit.
        controller?.tracker?.shutdown()
    }
}

/// `./run.sh dump`: prints today's recorded intervals as text, for checking tracking by hand.
enum DumpCommand {
    static func run() -> Int32 {
        let calendar = Calendar.autoupdatingCurrent
        let path = TrackerStore.defaultPath()
        guard FileManager.default.fileExists(atPath: path) else {
            print("No data yet: \(path) doesn't exist. Launch TikTik first.")
            return 1
        }
        do {
            let store = try TrackerStore(path: path)
            let now = Date()
            let today = DateInterval(start: calendar.startOfDay(for: now), end: now)
            let intervals = try store.intervals(overlapping: today)

            let time = DateFormatter()
            time.dateFormat = "HH:mm:ss"
            print("TikTik · \(path)")
            print("Today, \(intervals.count) intervals (the one in progress is saved when it ends):")
            var totals: [ActivityState: TimeInterval] = [:]
            for interval in intervals {
                let clipped = interval.clipped(to: today) ?? interval
                totals[clipped.state, default: 0] += clipped.duration
                var line = "\(time.string(from: clipped.start))–\(time.string(from: clipped.end))  "
                line += pad(DurationFormat.short(clipped.duration), 8) + pad(name(clipped.state), 7)
                if let app = clipped.app { line += app.name + " (\(app.bundleID))" }
                if let domain = clipped.domain { line += " · " + domain }
                print(line)
            }
            let summary = [ActivityState.active, .idle, .away]
                .map { "\(name($0)) \(DurationFormat.short(totals[$0] ?? 0))" }
                .joined(separator: " · ")
            print("Totals: " + summary)
            print("Database size: " + String(format: "%.1f MB", Double(store.fileSize()) / 1_048_576))
            return 0
        } catch {
            print("Couldn't read the database: \(error.localizedDescription)")
            return 1
        }
    }

    private static func name(_ state: ActivityState) -> String {
        switch state {
        case .active: return "active"
        case .idle: return "idle"
        case .away: return "away"
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}

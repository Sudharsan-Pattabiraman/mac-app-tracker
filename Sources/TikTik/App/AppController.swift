import AppKit
import Combine
import Observation
import os
import SwiftUI
import TikTikCore
import TikTikStore
import UniformTypeIdentifiers

/// Builds and connects the app's pieces: preferences, state, tracker, menu bar, popover and windows.
@MainActor
final class AppController {
    let preferences: Preferences
    let state: AppState
    /// The real tracker; nil in sample mode or when the database couldn't be opened.
    private(set) var tracker: Tracker?
    private let statusItem: StatusItemController
    private let welcome = WelcomeWindowController()
    private let designReview = DesignReviewWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var minuteTimer: Timer?
    private var lastPause: PauseState?
    private var appliedLaunchAtLogin: Bool?
    private let log = Logger(subsystem: "app.tiktik", category: "app")

    init(sampleMode: Bool) {
        let preferences = Preferences()
        let sampleProvider: SampleUsageProvider? = sampleMode ? SampleUsageProvider() : nil
        var tracker: Tracker?
        let provider: any UsageProvider
        if let sampleProvider {
            provider = sampleProvider
        } else if let store = AppController.openStore() {
            let realTracker = Tracker(store: store, config: AppController.config(from: preferences),
                                      websiteTracking: preferences.websiteTracking)
            tracker = realTracker
            provider = RealUsageProvider(tracker: realTracker)
        } else {
            provider = EmptyUsageProvider()
        }
        let state = AppState(provider: provider, defaultTab: preferences.defaultTab)
        let panel = PopoverPanel(rootView: PopoverRoot()
            .environment(state)
            .environmentObject(preferences)
            .themed())

        self.preferences = preferences
        self.state = state
        self.tracker = tracker
        self.statusItem = StatusItemController(panel: panel)

        statusItem.onOpen = { [weak self] in
            guard let self else { return }
            self.state.resetForOpening(defaultTab: self.preferences.defaultTab)
            self.state.reload()
            // Live RAM while the popover is open; each sample also refreshes the numbers (every 5 s).
            self.tracker?.memory.start()
        }
        statusItem.onClose = { [weak self] in
            self?.tracker?.memory.stop()
        }

        if let tracker {
            connect(tracker)
            tracker.start()
        }

        // At launch, reflect the real login item state (the user may have changed it in System Settings).
        if tracker != nil, preferences.hasCompletedWelcome {
            preferences.launchAtLogin = LoginItem.isEnabled
            appliedLaunchAtLogin = preferences.launchAtLogin
        }

        // objectWillChange fires before the new value is stored; hopping to the next run loop pass reads it.
        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.preferencesChanged() }
            .store(in: &cancellables)
        observeState()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        minuteTimer?.tolerance = 5
        refreshMenuBar()

        if let sampleProvider {
            showDesignReview(provider: sampleProvider)
        } else if !preferences.hasCompletedWelcome {
            showWelcome()
        }
    }

    // MARK: Setup

    private static func openStore() -> TrackerStore? {
        do {
            return try TrackerStore(path: TrackerStore.defaultPath())
        } catch {
            Logger(subsystem: "app.tiktik", category: "app")
                .error("Couldn't open the database: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func config(from preferences: Preferences) -> TrackerConfig {
        TrackerConfig(idleThreshold: TimeInterval(preferences.idleMinutes * 60),
                      excludedBundleIDs: Set(preferences.excludedBundleIDs))
    }

    private func connect(_ tracker: Tracker) {
        tracker.onLiveChange = { [weak self] in self?.liveDataChanged() }
        tracker.onDataChange = { [weak self] in self?.liveDataChanged() }
        tracker.memory.onUpdate = { [weak self] in
            guard let self, self.statusItem.isPanelVisible else { return }
            self.state.reload()
        }
        tracker.browser.onAccessChange = { [weak self] in self?.state.reload() }

        let store = tracker.store
        let calendar = tracker.calendar
        state.actions = AppActions(
            requestBrowserAccess: { [weak tracker] in tracker?.browser.requestAccessForRunningBrowsers() },
            browserAccessSummary: { [weak tracker] in tracker?.browser.accessSummary() ?? "" },
            storageSummary: {
                let megabytes = Double(store.fileSize()) / 1_048_576
                return "182 days kept · " + String(format: "%.1f MB", megabytes)
            },
            exportCSV: { [weak self] kind, days in
                self?.exportCSV(kind: kind, days: days, store: store, calendar: calendar)
            },
            clearAllData: { [weak self, weak tracker] in
                guard let tracker else { return }
                self?.confirmClearAll(tracker: tracker)
            },
            runModal: { [weak self] body in
                if let self { self.statusItem.runModal(body) } else { body() }
            },
            canManageData: true
        )
    }

    // MARK: Changes

    private func preferencesChanged() {
        tracker?.apply(config: Self.config(from: preferences), websiteTracking: preferences.websiteTracking)
        // Only touch the login item once the user has seen the welcome screen's choice.
        if tracker != nil, preferences.hasCompletedWelcome, appliedLaunchAtLogin != preferences.launchAtLogin {
            appliedLaunchAtLogin = preferences.launchAtLogin
            LoginItem.set(preferences.launchAtLogin)
        }
        refreshMenuBar()
    }

    private func liveDataChanged() {
        refreshMenuBar()
        if statusItem.isPanelVisible { state.reload() }
    }

    // MARK: Menu bar

    func refreshMenuBar() {
        statusItem.setLabel(MenuBarLabel(
            style: preferences.menuBarStyle,
            activeToday: state.provider.activeToday(now: Date()),
            dailyGoal: TimeInterval(preferences.dailyGoalHours * 3600),
            isIdle: tracker?.engine.open.state == .idle,
            pause: state.pause
        ))
    }

    /// Re-renders whenever pause state or data change (Observation tracking re-arms itself).
    private func observeState() {
        withObservationTracking {
            _ = state.pause
            _ = state.dataRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.stateChanged()
                self?.observeState()
            }
        }
    }

    private func stateChanged() {
        if state.pause != lastPause {
            lastPause = state.pause
            tracker?.setPaused(state.pause != nil)
        }
        refreshMenuBar()
    }

    private func tick() {
        // A timed pause ends on its own.
        if let end = state.pause?.endDate, end <= Date() {
            state.pause = nil
        }
        refreshMenuBar()
    }

    // MARK: Data actions

    private func exportCSV(kind: ExportKind, days: Int, store: TrackerStore, calendar: Calendar) {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let csv: String
        do {
            // Covers everything saved so far; the interval in progress is saved when it ends.
            csv = try CSVExporter(store: store, calendar: calendar)
                .export(kind == .raw ? .raw : .daily, window: DateInterval(start: start, end: now))
        } catch {
            log.error("Export failed: \(error.localizedDescription, privacy: .public)")
            showError("Couldn't export", error)
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.title = "Export \(kind.title)"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "TikTik \(kind == .raw ? "intervals" : "daily") \(formatter.string(from: start)) to \(formatter.string(from: now)).csv"
        panel.canCreateDirectories = true

        statusItem.runModal {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                log.error("Writing the export failed: \(error.localizedDescription, privacy: .public)")
                showError("Couldn't save the file", error)
            }
        }
    }

    private func confirmClearAll(tracker: Tracker) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Clear all data?"
        alert.informativeText = "This permanently deletes all of TikTik's history on this Mac. It can't be undone."
        let clear = alert.addButton(withTitle: "Clear all data")
        clear.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        statusItem.runModal {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                try tracker.deleteAllData()
                log.info("All data cleared")
            } catch {
                log.error("Clearing data failed: \(error.localizedDescription, privacy: .public)")
                showError("Couldn't clear the data", error)
            }
        }
        state.reload()
        refreshMenuBar()
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        statusItem.runModal { _ = alert.runModal() }
    }

    // MARK: Windows

    func showWelcome() {
        welcome.show(WelcomeView { [weak self] in
            guard let self else { return }
            self.preferences.hasCompletedWelcome = true
            if self.tracker != nil {
                self.appliedLaunchAtLogin = self.preferences.launchAtLogin
                LoginItem.set(self.preferences.launchAtLogin)
            }
            self.welcome.close()
        }
        .environment(state)
        .environmentObject(preferences)
        .themed())
    }

    private func showDesignReview(provider: SampleUsageProvider) {
        designReview.show(DesignReviewView(
            provider: provider,
            openPopover: { [weak self] in self?.statusItem.showPanel() },
            showWelcome: { [weak self] in self?.showWelcome() }
        )
        .environment(state)
        .environmentObject(preferences)
        .themed())
    }
}

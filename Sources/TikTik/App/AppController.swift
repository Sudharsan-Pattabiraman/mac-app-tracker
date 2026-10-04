import AppKit
import Combine
import Observation
import SwiftUI
import TikTikCore

/// Builds and connects the app's pieces: preferences, state, menu bar, popover and windows.
@MainActor
final class AppController {
    let preferences: Preferences
    let state: AppState
    private let statusItem: StatusItemController
    private let welcome = WelcomeWindowController()
    private let designReview = DesignReviewWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var minuteTimer: Timer?

    init(sampleMode: Bool) {
        let preferences = Preferences()
        let sampleProvider: SampleUsageProvider? = sampleMode ? SampleUsageProvider() : nil
        let provider: any UsageProvider
        if let sampleProvider {
            provider = sampleProvider
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
        self.statusItem = StatusItemController(panel: panel)

        statusItem.onOpen = { [weak self] in
            guard let self else { return }
            self.state.resetForOpening(defaultTab: self.preferences.defaultTab)
            self.state.reload()
        }

        // Redraw the menu bar when preferences or pause state change, and once a minute.
        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenuBar() }
            .store(in: &cancellables)
        observeState()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        minuteTimer?.tolerance = 5
        refreshMenuBar()

        if let sampleProvider {
            showDesignReview(provider: sampleProvider)
        } else if !preferences.hasCompletedWelcome {
            showWelcome()
        }
    }

    // MARK: Menu bar

    func refreshMenuBar() {
        statusItem.setLabel(MenuBarLabel(
            style: preferences.menuBarStyle,
            activeToday: state.provider.activeToday(now: Date()),
            dailyGoal: TimeInterval(preferences.dailyGoalHours * 3600),
            isIdle: false,
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
                self?.refreshMenuBar()
                self?.observeState()
            }
        }
    }

    private func tick() {
        // A timed pause ends on its own.
        if let end = state.pause?.endDate, end <= Date() {
            state.pause = nil
        }
        refreshMenuBar()
    }

    // MARK: Windows

    func showWelcome() {
        welcome.show(WelcomeView { [weak self] in
            self?.preferences.hasCompletedWelcome = true
            self?.welcome.close()
        }
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

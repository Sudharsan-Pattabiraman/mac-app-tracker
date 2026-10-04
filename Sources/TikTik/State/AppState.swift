import Foundation
import Observation
import TikTikCore

/// Pause state (SPEC 2.8, 5.3).
enum PauseState: Equatable {
    case until(Date)
    case indefinitely

    var endDate: Date? {
        if case .until(let date) = self { return date }
        return nil
    }
}

/// Where the popover is showing.
enum PopoverRoute: Equatable {
    case home
    case detail(AppIdentity)
    case settings
}

/// Shared UI state for the popover, menu bar and welcome window.
@MainActor
@Observable
final class AppState {
    var selectedTab: TimeTab
    /// App detail uses only the six ranges; it follows the main tab unless that's Now.
    var detailTab: TimeTab = .h6
    var route: PopoverRoute = .home
    var sort: AppSort = .time
    var pause: PauseState?
    /// Bumped whenever the data source changes, so views reload.
    var dataRevision = 0
    /// Export, clear, permissions (wired by AppController).
    var actions = AppActions()

    private(set) var provider: any UsageProvider

    func setProvider(_ newProvider: any UsageProvider) {
        provider = newProvider
        dataRevision += 1
    }

    /// Forces visible views to reload their data.
    func reload() {
        dataRevision += 1
    }

    /// The popover opens on the user's default tab with the list sorted by time (SPEC 5.4).
    func resetForOpening(defaultTab: TimeTab) {
        route = .home
        selectedTab = defaultTab
        sort = .time
    }

    func openDetail(_ app: AppIdentity) {
        detailTab = selectedTab == .now ? .h6 : selectedTab
        route = .detail(app)
    }

    init(provider: any UsageProvider, defaultTab: TimeTab) {
        self.provider = provider
        self.selectedTab = defaultTab
    }
}

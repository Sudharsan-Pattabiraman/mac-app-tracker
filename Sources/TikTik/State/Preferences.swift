import Combine
import Foundation
import TikTikCore

/// The six menu bar styles (SPEC 5.7).
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconTime, icon, text, ring, ringTime, timeDot

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .iconTime: return "A"
        case .icon: return "B"
        case .text: return "C"
        case .ring: return "D"
        case .ringTime: return "E"
        case .timeDot: return "F"
        }
    }

    var title: String {
        switch self {
        case .iconTime: return "Icon + time"
        case .icon: return "Icon"
        case .text: return "Text"
        case .ring: return "Ring"
        case .ringTime: return "Ring + time"
        case .timeDot: return "Time + state"
        }
    }
}

/// User settings, persisted in UserDefaults (SPEC 5.9).
@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published var defaultTab: TimeTab { didSet { defaults.set(defaultTab.rawValue, forKey: Key.defaultTab) } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) } }
    @Published var dailyGoalHours: Int { didSet { defaults.set(dailyGoalHours, forKey: Key.dailyGoalHours) } }
    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: Key.idleMinutes) } }
    @Published var websiteTracking: Bool { didSet { defaults.set(websiteTracking, forKey: Key.websiteTracking) } }
    @Published var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) } }
    @Published var hasCompletedWelcome: Bool { didSet { defaults.set(hasCompletedWelcome, forKey: Key.hasCompletedWelcome) } }

    static let idleMinuteOptions = [1, 2, 3, 5, 10, 15, 20, 30]
    static let dailyGoalOptions = [2, 4, 6, 8, 10, 12]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        defaultTab = defaults.string(forKey: Key.defaultTab).flatMap(TimeTab.init(rawValue:)) ?? .h6
        menuBarStyle = defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .iconTime
        dailyGoalHours = defaults.object(forKey: Key.dailyGoalHours) as? Int ?? 8
        idleMinutes = defaults.object(forKey: Key.idleMinutes) as? Int ?? 5
        websiteTracking = defaults.object(forKey: Key.websiteTracking) as? Bool ?? true
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []
        hasCompletedWelcome = defaults.bool(forKey: Key.hasCompletedWelcome)
    }

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let defaultTab = "defaultTab"
        static let menuBarStyle = "menuBarStyle"
        static let dailyGoalHours = "dailyGoalHours"
        static let idleMinutes = "idleMinutes"
        static let websiteTracking = "websiteTracking"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let hasCompletedWelcome = "hasCompletedWelcome"
    }
}

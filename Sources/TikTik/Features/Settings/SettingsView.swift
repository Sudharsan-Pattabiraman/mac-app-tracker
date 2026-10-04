import AppKit
import SwiftUI
import TikTikCore
import UniformTypeIdentifiers

/// Settings page inside the popover (SPEC 5.9).
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        // Re-read permission and storage text whenever data or browser access changes.
        let _ = state.dataRevision
        return VStack(spacing: Space.s3) {
            ZStack {
                HStack {
                    BackButton()
                    Spacer()
                }
                Text("Settings").textStyle(.title)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Space.s3_5) {
                    general
                    tracking
                    data
                    about
                }
            }
        }
    }

    // MARK: Groups

    private var general: some View {
        SettingsGroup("General") {
            SettingRow("Launch at login", "Start TikTik when you log in.") {
                Toggle("", isOn: $preferences.launchAtLogin).toggleStyle(.tk).labelsHidden()
            }
            TKSeparator()
            SettingRow("Default tab", "Selected when you open the popover.") {
                TKSelect(selection: $preferences.defaultTab, options: TimeTab.allCases, title: \.label)
            }
            TKSeparator()
            SettingRow("Menu bar style", "What appears in the menu bar.") {
                TKSelect(selection: $preferences.menuBarStyle, options: MenuBarStyle.allCases,
                         title: { "\($0.letter) · \($0.title)" })
            }
            TKSeparator()
            SettingRow("Daily goal", "Used by the Ring styles (D, E).") {
                TKSelect(selection: $preferences.dailyGoalHours, options: Preferences.dailyGoalOptions,
                         title: { "\($0)h" })
            }
        }
    }

    private var tracking: some View {
        SettingsGroup("Tracking") {
            SettingRow("Idle after", "No input for this long counts as Idle, backdated to your last input.") {
                TKSelect(selection: $preferences.idleMinutes, options: Preferences.idleMinuteOptions,
                         title: { "\($0) min" })
            }
            TKSeparator()
            SettingRow("Website tracking", "Chrome, Brave, Edge. Domain only; Incognito is never recorded.") {
                Toggle("", isOn: $preferences.websiteTracking).toggleStyle(.tk).labelsHidden()
            }
            TKSeparator()
            SettingRow("Browser permissions", state.actions.browserAccessSummary()) {
                Button("Allow…", action: showPermissionMenu).buttonStyle(.tk(.outline, size: .small))
            }
            TKSeparator()
            SettingRow("Excluded apps", excludedDescription) {
                Button("Edit…", action: editExcludedApps).buttonStyle(.tk(.outline, size: .small))
            }
            TKSeparator()
            SettingRow("Pause tracking", "For 15 min, 1 hour, or until you resume.") {
                TKSelect(selection: pauseBinding, options: PauseOption.allCases, title: \.title)
            }
        }
    }

    private var data: some View {
        SettingsGroup("Data") {
            SettingRow("Export CSV", "Raw intervals or daily totals.") {
                Button("Export…", action: showExportMenu)
                    .buttonStyle(.tk(.outline, size: .small))
                    .disabled(!state.actions.canManageData)
            }
            TKSeparator()
            SettingRow("Storage", state.actions.storageSummary()) {
                EmptyView()
            }
            TKSeparator()
            SettingRow("Clear all data", "Permanently deletes all history. Asks first.") {
                Button("Clear…") { state.actions.clearAllData() }
                    .buttonStyle(.tk(.destructive, size: .small))
                    .disabled(!state.actions.canManageData)
            }
        }
    }

    private var about: some View {
        SettingsGroup("About") {
            SettingRow("TikTik \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? TikTikCore.version)",
                       "Everything stays on this Mac.") {
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.tk(.outline, size: .small))
            }
        }
    }

    // MARK: Pause

    private enum PauseOption: CaseIterable, Hashable {
        case off, fifteenMinutes, oneHour, untilResumed

        var title: String {
            switch self {
            case .off: return "Off"
            case .fifteenMinutes: return "15 min"
            case .oneHour: return "1 hour"
            case .untilResumed: return "Until resumed"
            }
        }
    }

    private var pauseBinding: Binding<PauseOption> {
        Binding(
            get: {
                switch state.pause {
                case .none: return .off
                case .indefinitely: return .untilResumed
                // A pause of more than 15 minutes left can only be the 1-hour one.
                case .until(let end): return end.timeIntervalSinceNow > 15 * 60 ? .oneHour : .fifteenMinutes
                }
            },
            set: { option in
                switch option {
                case .off: state.pause = nil
                case .fifteenMinutes: state.pause = .until(Date().addingTimeInterval(15 * 60))
                case .oneHour: state.pause = .until(Date().addingTimeInterval(3600))
                case .untilResumed: state.pause = .indefinitely
                }
            }
        )
    }

    // MARK: Excluded apps

    private var excludedDescription: String {
        let names = preferences.excludedBundleIDs.map(Self.appName(for:))
        return names.isEmpty ? "Never recorded. None yet." : "Never recorded. " + names.joined(separator: ", ") + "."
    }

    private func editExcludedApps() {
        var items: [NativeMenu.Item] = [.init(title: "Add an app…") { addExcludedApp() }]
        for bundleID in preferences.excludedBundleIDs {
            items.append(.init(title: "Remove \(Self.appName(for: bundleID))") {
                preferences.excludedBundleIDs.removeAll { $0 == bundleID }
            })
        }
        NativeMenu.show(items: items)
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app TikTik should never record"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        state.actions.runModal {
            guard panel.runModal() == .OK else { return }
            for url in panel.urls {
                if let bundleID = Bundle(url: url)?.bundleIdentifier, !preferences.excludedBundleIDs.contains(bundleID) {
                    preferences.excludedBundleIDs.append(bundleID)
                }
            }
        }
    }

    // MARK: Data

    private func showExportMenu() {
        var items: [NativeMenu.Item] = []
        for kind in [ExportKind.daily, .raw] {
            for days in [7, 30, 182] {
                items.append(.init(title: "\(kind.title) · last \(days) days") {
                    state.actions.exportCSV(kind, days)
                })
            }
        }
        NativeMenu.show(items: items)
    }

    // MARK: Browser access

    private func showPermissionMenu() {
        NativeMenu.show(items: [
            .init(title: "Ask running browsers for access") { state.actions.requestBrowserAccess() },
            .init(title: "Open Automation settings…") { openAutomationSettings() },
        ])
    }

    private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A labelled group of setting rows in a card.
struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1_5) {
            Text(title).textStyle(.label).padding(.leading, Space.s0_5)
            TKCard(padding: CardPadding.none) {
                VStack(spacing: 0) { content }
            }
        }
    }
}

/// One setting: name and description on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let description: String
    let control: Control

    init(_ title: String, _ description: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s0_5) {
                Text(title).textStyle(.bodyStrong)
                Text(description).textStyle(.label).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, Space.s3_5)
        .padding(.vertical, Space.s2_5 + 1)
    }
}

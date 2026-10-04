import Foundation

/// Data export choices (SPEC 4).
enum ExportKind: String, CaseIterable {
    case daily, raw

    var title: String {
        switch self {
        case .daily: return "Daily totals"
        case .raw: return "Raw intervals"
        }
    }
}

/// Side-effecting actions the views can trigger. The real app wires them to the tracker;
/// sample mode leaves the harmless defaults.
struct AppActions {
    var requestBrowserAccess: () -> Void = {}
    var browserAccessSummary: () -> String = { "Chrome — · Brave — · Edge —" }
    var storageSummary: () -> String = { "182 days kept · cleaned daily" }
    var exportCSV: (ExportKind, _ days: Int) -> Void = { _, _ in }
    var clearAllData: () -> Void = {}
    /// False in sample mode, where there's no real data to export or clear.
    var canManageData = false
}

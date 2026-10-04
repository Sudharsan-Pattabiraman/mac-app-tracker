import Foundation
import os
import ServiceManagement

/// Launch at login via SMAppService (macOS 13+). Requires the app to live in an Applications folder,
/// which run.sh takes care of.
enum LoginItem {
    private static let log = Logger(subsystem: "app.tiktik", category: "login-item")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Couldn't change login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}

import AppKit

/// Entry point. TikTik is a menu-bar-only app (LSUIElement), so it runs an
/// NSApplication with the accessory activation policy and no main window.
@main
@MainActor
enum TikTikMain {
    static func main() {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.registerBundledFonts()
        let sampleMode = CommandLine.arguments.contains("--sample-data")
        controller = AppController(sampleMode: sampleMode)
    }
}

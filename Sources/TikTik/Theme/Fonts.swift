import AppKit
import CoreText

/// Registers the bundled JetBrains Mono fonts for this process only (nothing is installed system-wide).
enum Fonts {
    /// PostScript names of the bundled faces.
    static let regular = "JetBrainsMono-Regular"
    static let medium = "JetBrainsMono-Medium"
    static let semibold = "JetBrainsMono-SemiBold"

    /// Registers every .ttf in TikTik.app/Contents/Resources/Fonts. Returns false if none could be registered.
    @discardableResult
    static func registerBundledFonts() -> Bool {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return false }

        let fonts = files.filter { $0.pathExtension.lowercased() == "ttf" }
        var allRegistered = !fonts.isEmpty
        for url in fonts {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                allRegistered = false
            }
        }
        return allRegistered
    }

    /// True when JetBrains Mono can actually be used (registered, or installed on the system).
    static var isAvailable: Bool {
        NSFont(name: regular, size: 12) != nil
    }
}

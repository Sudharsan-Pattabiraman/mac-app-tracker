import AppKit
import SwiftUI
import TikTikCore

/// Caches app icons by bundle ID (looked up once from the installed app).
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage?] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = image
        return image
    }
}

/// The app's real icon, or a lettered tile when the app isn't installed.
struct AppIconView: View {
    @Environment(\.palette) private var palette
    let app: AppIdentity?
    var size: CGFloat = Size.appIcon

    var body: some View {
        if let app, let image = AppIconCache.shared.icon(for: app.bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            let shape = RoundedRectangle(cornerRadius: size >= Size.appIconLarge ? Radius.md : Radius.sm, style: .continuous)
            Text(initials)
                .font(.custom(Fonts.semibold, size: size * 0.45))
                .foregroundStyle(palette.mutedForeground)
                .frame(width: size, height: size)
                .background(app == nil ? .clear : palette.secondary, in: shape)
                .overlay(shape.strokeBorder(palette.border,
                                            style: StrokeStyle(lineWidth: Size.border, dash: app == nil ? [3, 2] : [])))
        }
    }

    private var initials: String {
        guard let name = app?.name else { return "" }
        return String(name.filter { !$0.isWhitespace }.prefix(2))
    }
}

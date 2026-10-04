import Foundation

/// Duration strings as specified in SPEC 5.4: `2h 14m`, `6h 06m`, `38h 12m`, `47m`, `<1m`, `0m`.
public enum DurationFormat {
    /// Hours and minutes. Minutes are zero-padded when hours are present; hours never roll into days.
    /// Partial minutes are truncated, so 59 seconds shows as `<1m`. Under a second counts as nothing: `0m`.
    public static func short(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "0m" }
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 1 { return "<1m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(pad(minutes))m" : "\(minutes)m"
    }

    /// Live timer used by the Now tab: `47m 12s` under an hour, `1h 02m` from an hour on.
    public static func timer(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? "\(hours)h \(pad(minutes))m" : "\(minutes)m \(pad(secs))s"
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

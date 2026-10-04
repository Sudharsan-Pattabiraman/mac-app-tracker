import Foundation

/// Memory strings for the RAM column (SPEC 5.4): `612 MB` below 1 GB, `2.1 GB` from 1 GB on.
/// Uses binary units, matching Activity Monitor.
public enum MemoryFormat {
    public static let megabyte: UInt64 = 1 << 20
    public static let gigabyte: UInt64 = 1 << 30

    /// Apps at or above this footprint are drawn in bold ("heavy").
    public static let heavyThreshold: UInt64 = 2 * gigabyte

    /// `nil` (app not running) renders as an em dash.
    public static func string(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        if bytes >= gigabyte {
            let tenths = (bytes * 10 + gigabyte / 2) / gigabyte   // rounded to one decimal
            return "\(tenths / 10).\(tenths % 10) GB"
        }
        let megabytes = max(1, (bytes + megabyte / 2) / megabyte)
        return "\(megabytes) MB"
    }

    public static func isHeavy(_ bytes: UInt64?) -> Bool {
        guard let bytes else { return false }
        return bytes >= heavyThreshold
    }
}

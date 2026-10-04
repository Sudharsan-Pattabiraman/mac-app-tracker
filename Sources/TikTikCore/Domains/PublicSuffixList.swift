import Foundation

/// Mozilla's Public Suffix List, used to reduce hosts to registrable domains (SPEC 2.5):
/// `mail.google.com` → `google.com`, `a.b.co.uk` → `b.co.uk`, `me.github.io` → `me.github.io`.
public struct PublicSuffixList: Sendable {
    private let exact: Set<String>
    private let wildcards: Set<String>     // "*.ck" stored as "ck"
    private let exceptions: Set<String>    // "!www.ck" stored as "www.ck"

    /// Parses the standard `public_suffix_list.dat` format.
    public init(contents: String) {
        var exact = Set<String>()
        var wildcards = Set<String>()
        var exceptions = Set<String>()
        contents.enumerateLines { line, _ in
            // Rules are the first whitespace-delimited token; comments start with "//".
            guard let rule = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init),
                  !rule.hasPrefix("//") else { return }
            let lowered = rule.lowercased()
            if lowered.hasPrefix("!") {
                exceptions.insert(String(lowered.dropFirst()))
            } else if lowered.hasPrefix("*.") {
                wildcards.insert(String(lowered.dropFirst(2)))
            } else {
                exact.insert(lowered)
            }
        }
        self.exact = exact
        self.wildcards = wildcards
        self.exceptions = exceptions
    }

    public var ruleCount: Int { exact.count + wildcards.count + exceptions.count }

    /// The registrable domain for a host, or the host itself for IP addresses, single labels
    /// (`localhost`) and hosts that are themselves public suffixes.
    public func registrableDomain(forHost rawHost: String) -> String? {
        var host = rawHost.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }
        if Self.isIPAddress(host) { return host }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count > 1, !labels.contains(where: \.isEmpty) else { return host }

        // Find the longest matching public suffix; exceptions beat wildcards (PSL algorithm).
        var suffixLabelCount = 1   // default rule "*"
        for index in labels.indices {
            let candidate = labels[index...].joined(separator: ".")
            if exceptions.contains(candidate) {
                suffixLabelCount = labels.count - index - 1
                break
            }
            if exact.contains(candidate) {
                suffixLabelCount = labels.count - index
                break
            }
            if index + 1 < labels.count, wildcards.contains(labels[(index + 1)...].joined(separator: ".")) {
                suffixLabelCount = labels.count - index
                break
            }
        }

        guard labels.count > suffixLabelCount else { return host }
        return labels[(labels.count - suffixLabelCount - 1)...].joined(separator: ".")
    }

    /// The registrable domain of an http(s) URL; nil for other schemes (chrome://, file://, about:).
    public func registrableDomain(forURL urlString: String) -> String? {
        guard let components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        // URLComponents keeps IPv6 brackets on some platforms.
        let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        return registrableDomain(forHost: bare)
    }

    static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }   // IPv6
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Int(part), !part.isEmpty, part.count <= 3 else { return false }
            return (0...255).contains(value)
        }
    }
}

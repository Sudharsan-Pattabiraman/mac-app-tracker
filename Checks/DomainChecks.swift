import Foundation
import TikTikCore

/// PublicSuffixList against a small fixed list, then against the bundled real list.
func domainChecks(_ h: inout Harness) {
    let psl = PublicSuffixList(contents: """
        // comment
        com
        uk
        co.uk
        io
        github.io
        br
        *.nom.br
        *.ck
        !www.ck
        """)

    h.group("PublicSuffixList: rules") { h in
        h.equal(psl.ruleCount, 9)
        h.equal(psl.registrableDomain(forHost: "mail.google.com"), "google.com")
        h.equal(psl.registrableDomain(forHost: "GitHub.com."), "github.com", "case and trailing dot")
        h.equal(psl.registrableDomain(forHost: "a.b.co.uk"), "b.co.uk")
        h.equal(psl.registrableDomain(forHost: "me.github.io"), "me.github.io", "private suffix")
        h.equal(psl.registrableDomain(forHost: "github.io"), "github.io", "a suffix itself")
        h.equal(psl.registrableDomain(forHost: "x.a.b.nom.br"), "a.b.nom.br", "wildcard")
        h.equal(psl.registrableDomain(forHost: "www.ck"), "www.ck", "exception")
        h.equal(psl.registrableDomain(forHost: "a.www.ck"), "www.ck", "exception subdomain")
        h.equal(psl.registrableDomain(forHost: "foo.example"), "foo.example", "unknown TLD uses default rule")
        h.equal(psl.registrableDomain(forHost: "localhost"), "localhost")
        h.equal(psl.registrableDomain(forHost: "192.168.1.20"), "192.168.1.20", "IPv4 stays as is")
        h.equal(psl.registrableDomain(forHost: ""), nil)
    }

    h.group("PublicSuffixList: URLs") { h in
        h.equal(psl.registrableDomain(forURL: "https://docs.google.com/document/d/1"), "google.com")
        h.equal(psl.registrableDomain(forURL: "http://localhost:3000/app"), "localhost")
        h.equal(psl.registrableDomain(forURL: "chrome://newtab/"), nil, "browser pages have no domain")
        h.equal(psl.registrableDomain(forURL: "file:///Users/me/a.html"), nil)
        h.equal(psl.registrableDomain(forURL: "about:blank"), nil)
        h.equal(psl.registrableDomain(forURL: "https://[::1]:8080/"), "::1", "IPv6")
    }

    h.group("PublicSuffixList: bundled list") { h in
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TikTik/Resources/public_suffix_list.dat").path
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            h.expect(false, "bundled list readable at \(path)")
            return
        }
        let real = PublicSuffixList(contents: contents)
        h.expect(real.ruleCount > 9_000, "thousands of rules")
        h.equal(real.registrableDomain(forHost: "www.bbc.co.uk"), "bbc.co.uk")
        h.equal(real.registrableDomain(forHost: "user.github.io"), "user.github.io")
        h.equal(real.registrableDomain(forHost: "studio.youtube.com"), "youtube.com")
        h.equal(real.registrableDomain(forHost: "a.b.s3.amazonaws.com"), "b.s3.amazonaws.com")
    }
}

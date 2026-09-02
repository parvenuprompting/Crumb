import Foundation

struct WhitelistStore: Codable, Sendable {
    var domains: [String] = []

    /// Test-seam: laat tests naar een tijdelijk bestand schrijven.
    static var overrideFileURL: URL?

    static var fileURL: URL {
        overrideFileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crumb", isDirectory: true)
            .appendingPathComponent("whitelist.json")
    }

    static func load() -> WhitelistStore {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(WhitelistStore.self, from: data) else {
            return WhitelistStore()
        }
        return store
    }

    func save() throws {
        let dir = Self.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
    }

    /// Brengt willekeurige gebruikersinvoer terug tot een kaal domein:
    /// scheme, pad, query, poort, volledige hoofdletters en `www.` verdwijnen.
    /// Invoer zoals `https://bank.nl/login`, `bank.nl:443` of `WWW.Example.COM`
    /// wordt allemaal `bank.nl` / `example.com`.
    static func normalizedDomain(_ input: String) -> String {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return "" }

        // URL-achtige invoer (scheme, pad, query, anchor) terugbrengen tot de host.
        if raw.contains("/") || raw.contains("?") || raw.contains("#") {
            var candidate = raw
            if !candidate.contains("://") { candidate = "https://" + candidate }
            if let url = URL(string: candidate), let host = url.host, !host.isEmpty {
                raw = host
            }
        }

        // Poort eraf, maar alleen als het echt een poortnummer is (IPv6 niet breken).
        if let colonIndex = raw.firstIndex(of: ":") {
            let after = raw[raw.index(after: colonIndex)...]
            if !after.isEmpty, after.allSatisfy(\.isNumber) {
                raw = String(raw[..<colonIndex])
            }
        }

        if raw.hasPrefix(".") { raw = String(raw.dropFirst()) }
        if raw.hasPrefix("www.") { raw = String(raw.dropFirst(4)) }
        return raw
    }

    /// Minimale sanity-check voor whitelist-invoer: een domein heeft minstens
    /// één punt en geen pad-, poort- of spatietekens.
    static func isValidWhitelistDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty else { return false }
        return domain.contains(".")
            && !domain.contains("/")
            && !domain.contains(":")
            && !domain.contains(" ")
    }
}

struct SafelistEngine: Sendable {
    let whitelist: Set<String>
    var protectedCookies: Set<String> = []

    static let authExactTokens: Set<String> = [
        "session", "sess", "sid", "ssid", "auth", "token", "csrf", "xsrf", "jwt",
        "login", "signin", "remember", "rememberme", "userid", "user_id", "uid"
    ]

    static let authCompoundPatterns: Set<String> = [
        "sessionid", "sessiontoken", "sessionkey", "sessionsig",
        "authtoken", "accesstoken", "refreshtoken", "logintoken", "idtoken",
        "jsessionid", "phpsessid", "aspsessionid", "csrftoken", "xsrf-token"
    ]

    func evaluate(
        domain: String,
        name: String,
        path: String = "/",
        isSecure: Bool,
        isHttpOnly: Bool,
        isSessionOnly: Bool,
        creation: Date?,
        now: Date = Date()
    ) -> CookieProtection {
        if protectedCookies.contains(ProtectedCookieStore.key(domain: domain, name: name, path: path)) {
            return .locked("Handmatig beschermd door de gebruiker — nooit wissen.")
        }
        if let reason = whitelistReason(domain: domain) {
            return .locked(reason)
        }
        if let reason = Self.authPatternReason(name: name) {
            return .locked(reason)
        }
        if let reason = Self.recentSessionReason(
            isSecure: isSecure,
            isHttpOnly: isHttpOnly,
            isSessionOnly: isSessionOnly,
            creation: creation,
            now: now
        ) {
            return .reviewOnly(reason)
        }
        return .none
    }

    private func whitelistReason(domain: String) -> String? {
        let normalized = domain.lowercased()
        for entry in whitelist {
            if normalized == entry || normalized.hasSuffix(".\(entry)") {
                return "Staat op de gebruikerswhitelist ('\(entry)') — nooit wissen."
            }
        }
        return nil
    }

    static func authPatternReason(name: String) -> String? {
        let lower = name.lowercased()
        if lower.hasPrefix("__secure-") || lower.hasPrefix("__host-") {
            return "Naam met auth-prefix (\(name.hasPrefix("__Host") ? "__Host-" : "__Secure-")) — sessiecookie."
        }
        let tokens = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if tokens.contains(where: { authExactTokens.contains($0) }) {
            if let token = tokens.first(where: { authExactTokens.contains($0) }) {
                return "Naam bevat auth-token ('\(token)') — sessiecookie."
            }
        }
        let joined = tokens.joined()
        for pattern in authCompoundPatterns {
            if joined.contains(pattern) {
                return "Naam matcht auth-patroon ('\(pattern)') — sessiecookie."
            }
        }
        return nil
    }

    static let recentSessionWindow: TimeInterval = 24 * 60 * 60

    private static func recentSessionReason(
        isSecure: Bool,
        isHttpOnly: Bool,
        isSessionOnly: Bool,
        creation: Date?,
        now: Date
    ) -> String? {
        guard isSecure, isHttpOnly, !isSessionOnly, let creation else { return nil }
        guard now.timeIntervalSince(creation) < recentSessionWindow else { return nil }
        return "Beveiligde cookie minder dan 24 uur geleden aangemaakt — mogelijk actieve sessie."
    }
}

import Foundation

struct ChromiumBrowserConfig: Sendable {
    let browserName: String
    let appSupportRelativePath: String

    static let chrome = ChromiumBrowserConfig(
        browserName: "Chrome",
        appSupportRelativePath: "Google/Chrome"
    )

    static let brave = ChromiumBrowserConfig(
        browserName: "Brave",
        appSupportRelativePath: "BraveSoftware/Brave-Browser"
    )
}

struct ChromiumSource: CookieSource {
    let config: ChromiumBrowserConfig
    private let fileManager = FileManager.default

    var browserName: String { config.browserName }

    var isInstalled: Bool { !Self.cookieStoreURLs(for: config).isEmpty }

    static func cookieStoreURLs(for config: ChromiumBrowserConfig) -> [URL] {
        let rootURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(config.appSupportRelativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "Cookies" {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir { urls.append(url) }
        }
        return urls
    }

    func scan() throws -> [RawCookie] {
        var cookies: [RawCookie] = []
        for storeURL in Self.cookieStoreURLs(for: config) {
            let copyURL = try StoreCopier.copyStore(at: storeURL)
            defer { try? fileManager.removeItem(at: copyURL.deletingLastPathComponent()) }
            cookies.append(contentsOf: try readStore(at: copyURL))
        }
        return cookies
    }

    private func readStore(at dbURL: URL) throws -> [RawCookie] {
        let db = try SQLiteDatabase(path: dbURL.path)
        let columns = try db.tableColumns(table: "cookies")

        var select = ["host_key", "name", "path", "is_secure", "is_httponly", "expires_utc"]
        var hasPersistent = false
        var hasCreation = false
        if columns.contains("is_persistent") {
            select.append("is_persistent")
            hasPersistent = true
        }
        if columns.contains("creation_utc") {
            select.append("creation_utc")
            hasCreation = true
        }

        let rows = try db.query("SELECT \(select.joined(separator: ", ")) FROM cookies")

        return rows.compactMap { row in
            guard let domain = row["host_key"]?.textValue, !domain.isEmpty,
                  let name = row["name"]?.textValue else { return nil }

            let expiresUseC = row["expires_utc"]?.intValue ?? 0
            let isPersistent = hasPersistent ? (row["is_persistent"]?.intValue ?? 1) != 0 : true
            let isSessionOnly = expiresUseC == 0 || !isPersistent
            let creation = hasCreation
                ? Self.dateFromChromiumEpoch(row["creation_utc"]?.intValue ?? 0)
                : nil

            return RawCookie(
                domain: Self.normalizedDomain(domain),
                name: name,
                path: row["path"]?.textValue ?? "/",
                expiry: Self.dateFromChromiumEpoch(expiresUseC),
                creation: creation,
                isSecure: (row["is_secure"]?.intValue ?? 0) != 0,
                isHttpOnly: (row["is_httponly"]?.intValue ?? 0) != 0,
                isSessionOnly: isSessionOnly
            )
        }
    }

    static func normalizedDomain(_ host: String) -> String {
        host.hasPrefix(".") ? String(host.dropFirst()) : host
    }

    static func dateFromChromiumEpoch(_ microSeconds: Int64) -> Date? {
        guard microSeconds > 0 else { return nil }
        let unixSeconds = microSeconds / 1_000_000 - 11_644_473_600
        return Date(timeIntervalSince1970: TimeInterval(unixSeconds))
    }
}

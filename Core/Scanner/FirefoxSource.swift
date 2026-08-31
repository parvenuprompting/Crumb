import Foundation

struct FirefoxSource: CookieSource {
    let browserName = "Firefox"
    private let fileManager = FileManager.default

    var profilesRootURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
    }

    var isInstalled: Bool { fileManager.fileExists(atPath: profilesRootURL.path) }

    static func cookieStoreURLs() -> [URL] {
        let profilesRootURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: profilesRootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        return entries
            .filter { $0.resolvingSymlinksInPath().hasDirectoryPath }
            .compactMap { profileDir -> URL? in
                let store = profileDir.appendingPathComponent("cookies.sqlite")
                return FileManager.default.fileExists(atPath: store.path) ? store : nil
            }
    }

    private var cookieStoreURLs: [URL] { Self.cookieStoreURLs() }

    func scan() throws -> [RawCookie] {
        var cookies: [RawCookie] = []
        for storeURL in cookieStoreURLs {
            let copyURL = try StoreCopier.copyStore(at: storeURL)
            defer { try? fileManager.removeItem(at: copyURL.deletingLastPathComponent()) }
            cookies.append(contentsOf: try readStore(at: copyURL))
        }
        return cookies
    }

    private func readStore(at dbURL: URL) throws -> [RawCookie] {
        let db = try SQLiteDatabase(path: dbURL.path)
        let columns = try db.tableColumns(table: "moz_cookies")

        var select = ["name", "host", "path", "expiry", "isSecure", "isHttpOnly"]
        var hasCreation = false
        var hasInBrowserElement = false
        if columns.contains("creationTime") {
            select.append("creationTime")
            hasCreation = true
        }
        if columns.contains("inBrowserElement") {
            select.append("inBrowserElement")
            hasInBrowserElement = true
        }

        let rows = try db.query("SELECT \(select.joined(separator: ", ")) FROM moz_cookies")

        return rows.compactMap { row in
            guard let host = row["host"]?.textValue, !host.isEmpty,
                  let name = row["name"]?.textValue else { return nil }

            let expiryUnix = row["expiry"]?.intValue ?? 0
            let isSessionOnly = expiryUnix == 0
            let creation = hasCreation
                ? Self.dateFromFirefoxCreation(row["creationTime"]?.intValue ?? 0)
                : nil

            return RawCookie(
                domain: Self.normalizedDomain(host),
                name: name,
                path: row["path"]?.textValue ?? "/",
                expiry: expiryUnix > 0 ? Date(timeIntervalSince1970: TimeInterval(expiryUnix)) : nil,
                creation: creation,
                isSecure: (row["isSecure"]?.intValue ?? 0) != 0,
                isHttpOnly: (row["isHttpOnly"]?.intValue ?? 0) != 0,
                isSessionOnly: isSessionOnly
            )
        }
    }

    static func normalizedDomain(_ host: String) -> String {
        host.hasPrefix(".") ? String(host.dropFirst()) : host
    }

    static func dateFromFirefoxCreation(_ microSeconds: Int64) -> Date? {
        guard microSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(microSeconds) / 1_000_000)
    }
}

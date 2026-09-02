import Foundation
import AppKit

struct DeletionResult: Sendable {
    let record: CookieRecord
    let success: Bool
    let detail: String
}

enum DeletionEngine {
    static let browserBundleIDs: [String: String] = [
        "Chrome": "com.google.Chrome",
        "Brave": "com.brave.Browser",
        "Firefox": "org.mozilla.firefox"
    ]

    static func isBrowserRunning(_ browser: String) -> Bool {
        guard let bundleID = browserBundleIDs[browser],
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        return !app.isTerminated
    }

    static func canDelete(_ record: CookieRecord) -> (allowed: Bool, reason: String?) {
        if record.protection.isLocked {
            return (false, "Geblokkeerd door safelist.")
        }
        if record.browser == "Safari" {
            return (false, "Verwijderen in Safari wordt niet ondersteund (geen veilige schrijftoegang tot het cookie-bestand).")
        }
        return (true, nil)
    }

    /// Cookie-store URLs per browser; test-seam via de `stores`-parameter.
    static func stores(for browser: String) -> [URL] {
        switch browser {
        case "Chrome": return ChromiumSource.cookieStoreURLs(for: .chrome)
        case "Brave": return ChromiumSource.cookieStoreURLs(for: .brave)
        case "Firefox": return FirefoxSource.cookieStoreURLs()
        default: return []
        }
    }

    static func delete(_ records: [CookieRecord]) async -> [DeletionResult] {
        var results: [DeletionResult] = []
        var deletable: [CookieRecord] = []

        for record in records {
            let gate = canDelete(record)
            guard gate.allowed else {
                results.append(DeletionResult(record: record, success: false, detail: gate.reason ?? "geblokkeerd"))
                continue
            }
            if isBrowserRunning(record.browser) {
                results.append(DeletionResult(record: record, success: false, detail: "\(record.browser) draait — sluit de browser af en probeer opnieuw."))
                continue
            }
            deletable.append(record)
        }
        guard !deletable.isEmpty else { return results }

        // Eerst de volledige rijen back-uppen (met waarden), dan pas verwijderen.
        // Lukt de back-up niet, dan wordt er ook niet verwijderd.
        let backupEntries = captureRows(for: deletable)
        do {
            try CookieBackupStore.write(entries: backupEntries)
        } catch {
            for record in deletable {
                results.append(DeletionResult(
                    record: record,
                    success: false,
                    detail: "Back-up mislukt (\(error.localizedDescription)) — niet verwijderd."
                ))
            }
            return results
        }

        for record in deletable {
            do {
                let removed = try deleteInStore(record: record)
                results.append(DeletionResult(
                    record: record,
                    success: removed > 0,
                    detail: removed > 0 ? "verwijderd (\(removed) rij)" : "niet gevonden in cookie-opslag"
                ))
            } catch {
                results.append(DeletionResult(record: record, success: false, detail: error.localizedDescription))
            }
        }
        return results
    }

    /// Leest de volledige rijen die verwijderd gaan worden, zodat ze via een
    /// back-up teruggezet kunnen worden. `stores`-parameter is een test-seam.
    static func captureRows(
        for records: [CookieRecord],
        stores: [String: [URL]]? = nil
    ) -> [CookieBackupEntry] {
        var entries: [CookieBackupEntry] = []
        let grouped = Dictionary(grouping: records, by: \.browser)

        for (browser, group) in grouped {
            let storeURLs = stores?[browser] ?? Self.stores(for: browser)
            let table = browser == "Firefox" ? "moz_cookies" : "cookies"
            let hostColumn = browser == "Firefox" ? "host" : "host_key"

            for storeURL in storeURLs {
                guard let db = try? SQLiteDatabase(path: storeURL.path) else { continue }
                for record in group {
                    let sql = "SELECT * FROM \(table) WHERE (\(hostColumn) = ? OR \(hostColumn) = ?) AND name = ? AND path = ?"
                    let parameters: [SQLiteValue] = [
                        .text(record.domain),
                        .text("." + record.domain),
                        .text(record.name),
                        .text(record.path)
                    ]
                    guard let rows = try? db.query(sql, parameters: parameters) else { continue }
                    for row in rows {
                        entries.append(CookieBackupEntry(
                            storePath: storeURL.path,
                            table: table,
                            browser: browser,
                            values: row.mapValues(BackupValue.init)
                        ))
                    }
                }
            }
        }
        return entries
    }

    private static func deleteInStore(record: CookieRecord) throws -> Int {
        switch record.browser {
        case "Chrome":
            return try deleteChromium(config: .chrome, record: record)
        case "Brave":
            return try deleteChromium(config: .brave, record: record)
        case "Firefox":
            return try deleteFirefox(record: record)
        default:
            return 0
        }
    }

    private static func deleteChromium(config: ChromiumBrowserConfig, record: CookieRecord) throws -> Int {
        var removed = 0
        for storeURL in ChromiumSource.cookieStoreURLs(for: config) {
            let db = try SQLiteDatabase(path: storeURL.path, readWrite: true)
            for host in [record.domain, "." + record.domain] {
                removed += try db.execute(
                    "DELETE FROM cookies WHERE host_key = ? AND name = ? AND path = ?",
                    parameters: [host, record.name, record.path]
                )
            }
        }
        return removed
    }

    private static func deleteFirefox(record: CookieRecord) throws -> Int {
        var removed = 0
        for storeURL in FirefoxSource.cookieStoreURLs() {
            let db = try SQLiteDatabase(path: storeURL.path, readWrite: true)
            for host in [record.domain, "." + record.domain] {
                removed += try db.execute(
                    "DELETE FROM moz_cookies WHERE host = ? AND name = ? AND path = ?",
                    parameters: [host, record.name, record.path]
                )
            }
        }
        return removed
    }
}

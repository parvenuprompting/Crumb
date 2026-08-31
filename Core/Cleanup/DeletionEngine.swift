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

    static func delete(_ records: [CookieRecord]) async -> [DeletionResult] {
        var results: [DeletionResult] = []
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

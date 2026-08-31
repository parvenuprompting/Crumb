import Foundation

@MainActor
final class ScanService: ObservableObject {
    static let shared = ScanService()

    @Published private(set) var isScanning = false
    @Published private(set) var lastRun: ScanRun?
    @Published private(set) var lastError: String?

    private let fileManager = FileManager.default

    var sourceAvailability: [SourceAvailability] {
        Self.buildSources().map { source in
            let safariAccess = (source as? SafariSource)?.isAccessible ?? true
            let installed = source.isInstalled
            return SourceAvailability(
                browser: source.browserName,
                isInstalled: installed,
                isAccessible: safariAccess,
                requiresFullDiskAccess: source is SafariSource && !safariAccess
            )
        }
    }

    struct SourceAvailability: Identifiable, Hashable {
        let browser: String
        let isInstalled: Bool
        let isAccessible: Bool
        let requiresFullDiskAccess: Bool

        var id: String { browser }
    }

    static func buildSources() -> [any CookieSource] {
        [
            ChromiumSource(config: .chrome),
            ChromiumSource(config: .brave),
            SafariSource(),
            FirefoxSource()
        ]
    }

    func checkAvailability() {
        objectWillChange.send()
    }

    func runScan() async {
        guard !isScanning else { return }
        isScanning = true
        lastError = nil
        defer { isScanning = false }

        let startedAt = Date()
        let sources = Self.buildSources()
        let whitelistStore = WhitelistStore.load()
        let safelist = SafelistEngine(whitelist: Set(whitelistStore.domains.map(WhitelistStore.normalizedDomain)))
        let now = Date()

        guard let trackerList = TrackerList() else {
            lastError = "Tracker-domeinenlijst ontbreekt in de app-bundle."
            return
        }
        let engine = RuleEngine(trackerList: trackerList, now: now)

        var statuses: [ScanSourceStatus] = []
        var rawCookies: [RawCookie] = []
        rawCookies.reserveCapacity(2000)

        for source in sources {
            guard source.isInstalled else {
                statuses.append(ScanSourceStatus(browser: source.browserName, scanned: false, cookieCount: 0, error: nil, requiresFullDiskAccess: false))
                continue
            }
            do {
                let cookies = try source.scan().map { raw -> RawCookie in
                    var tagged = raw
                    tagged.browser = source.browserName
                    return tagged
                }
                rawCookies.append(contentsOf: cookies)
                statuses.append(ScanSourceStatus(browser: source.browserName, scanned: true, cookieCount: cookies.count, error: nil, requiresFullDiskAccess: false))
            } catch CookieScanError.fullDiskAccessRequired {
                statuses.append(ScanSourceStatus(browser: source.browserName, scanned: false, cookieCount: 0, error: "Volledige Schijftoegang vereist", requiresFullDiskAccess: true))
            } catch {
                statuses.append(ScanSourceStatus(browser: source.browserName, scanned: false, cookieCount: 0, error: error.localizedDescription, requiresFullDiskAccess: false))
            }
        }

        var snapshot = SnapshotStore.load()
        var records: [CookieRecord] = []
        records.reserveCapacity(rawCookies.count)

        for raw in rawCookies {
            let browserAgnosticID = "\(raw.domain)|\(raw.name)|\(raw.path)"

            let protection = safelist.evaluate(
                domain: raw.domain,
                name: raw.name,
                isSecure: raw.isSecure,
                isHttpOnly: raw.isHttpOnly,
                isSessionOnly: raw.isSessionOnly,
                creation: raw.creation,
                now: now
            )
            let classified = engine.classify(raw: raw, protection: protection)

            var firstSeen = raw.creation ?? now
            var lastSeen = now
            if let seen = snapshot.entries[browserAgnosticID] {
                firstSeen = seen.firstSeen
                lastSeen = now
            }
            snapshot.recordLastSeen(browserAgnosticID, at: lastSeen, firstSeenFallback: firstSeen)

            records.append(CookieRecord(
                domain: raw.domain,
                name: raw.name,
                valueHash: Hashing.cookieValueHash(domain: raw.domain, name: raw.name, path: raw.path),
                browser: raw.browser,
                path: raw.path,
                expiry: raw.expiry,
                isSecure: raw.isSecure,
                isHttpOnly: raw.isHttpOnly,
                isSessionOnly: raw.isSessionOnly,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                category: classified.category,
                verdict: classified.verdict,
                reasoning: classified.reasoning,
                protection: protection
            ))
        }

        let finishedAt = Date()
        let run = ScanRun(startedAt: startedAt, finishedAt: finishedAt, sources: statuses, records: records)
        lastRun = run

        do {
            try snapshot.save()
            try JSONRunLog.write(run: run)
        } catch {
            lastError = "Kon run niet wegschrijven: \(error.localizedDescription)"
        }
    }
}

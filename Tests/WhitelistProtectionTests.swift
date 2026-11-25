import XCTest
@testable import Crumb

/// De belofte van de whitelist: een domein dat je dagelijks gebruikt komt
/// nooit in een verwijderlijst — niet bij een snelkeuze en niet bij de
/// automatische schoonmaak.
final class WhitelistProtectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        SnapshotStore.overrideFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-whitelist-\(UUID().uuidString).json")
        WhitelistStore.overrideFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-whitelist-store-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: SnapshotStore.fileURL)
        try? FileManager.default.removeItem(at: WhitelistStore.fileURL)
        SnapshotStore.overrideFileURL = nil
        WhitelistStore.overrideFileURL = nil
        super.tearDown()
    }

    private func raw(domain: String, name: String) -> RawCookie {
        RawCookie(
            domain: domain,
            name: name,
            path: "/",
            expiry: Date(timeIntervalSince1970: 2_000_000_000),
            creation: Date(timeIntervalSince1970: 1_000_000_000),
            isSecure: false,
            isHttpOnly: false,
            isSessionOnly: false
        )
    }

    /// Bouwt records via de echte pijplijn, zodat de whitelist ook echt
    /// als vergrendeling uit de safelist komt en niet uit de test zelf.
    private func records(domain: String, name: String, whitelist: [String]) async -> [CookieRecord] {
        await ScanService.buildRecords(
            rawCookies: [raw(domain: domain, name: name)],
            whitelist: Set(whitelist.map(WhitelistStore.normalizedDomain)),
            trackerList: TrackerList(suffixes: ["bandlab.com", "google.com", "adnxs.com"]),
            now: now
        )
    }

    private func run(_ records: [CookieRecord]) -> ScanRun {
        ScanRun(startedAt: now, finishedAt: now, sources: [], records: records)
    }

    func testWhitelistedTrackerGetsNoVerdictToClean() async {
        // bandlab.com staat op de lijst: zelfs als de trackerlijst het domein
        // kent, mag er geen opschoonadvies uitkomen.
        let recs = await records(domain: "bandlab.com", name: "tracking_id", whitelist: ["bandlab.com"])

        XCTAssertEqual(recs.first?.protection.isLocked, true)
        XCTAssertNotEqual(recs.first?.verdict, .safeToClean)
        XCTAssertNotEqual(recs.first?.verdict, .reviewSuggested)
    }

    func testSubdomainInheritsWhitelist() async {
        // google.com op de lijst dekt accounts.google.com.
        let recs = await records(domain: "accounts.google.com", name: "SID", whitelist: ["google.com"])
        XCTAssertEqual(recs.first?.protection.isLocked, true)
    }

    func testWhitelistedDomainNeverInAnyQuickCleanPreset() async {
        let beschermd = await records(domain: "bandlab.com", name: "ad_id", whitelist: ["bandlab.com"])
        let vrij = await records(domain: "adnxs.com", name: "uuid2", whitelist: ["bandlab.com"])
        let scanRun = run(beschermd + vrij)

        for preset in QuickCleanPreset.allCases {
            let kans = QuickCleanEngine.candidates(for: preset, in: scanRun, now: now)
            XCTAssertFalse(
                kans.contains { $0.domain == "bandlab.com" },
                "Preset \(preset) bevat een whitelist-domein"
            )
        }
        // Controle: zonder whitelist zou de tracker wél in de lijst staan,
        // dus de test meet echt de bescherming en niet een lege verzameling.
        let zonderWhitelist = run(await records(domain: "adnxs.com", name: "uuid2", whitelist: []))
        XCTAssertFalse(QuickCleanEngine.candidates(for: .marketingTracking, in: zonderWhitelist, now: now).isEmpty)
    }

    func testWhitelistedDomainNeverInAutoClean() async {
        let beschermd = await records(domain: "bandlab.com", name: "ad_id", whitelist: ["bandlab.com"])
        let scanRun = run(beschermd)

        let settings = AutoCleanSettings(
            enabled: true,
            includeMarketingTracking: true,
            includeAnalytics: true,
            minAgeDays: 0,
            maxPerRun: 100,
            minSafeCookies: 0
        )
        let kans = AutoCleanEngine.candidates(in: scanRun, settings: settings, now: now)
        XCTAssertTrue(kans.isEmpty)
    }

    func testRecommendedDomainsAreValidAndUnique() {
        let alle = RecommendedWhitelist.allDomains
        XCTAssertEqual(alle.count, Set(alle).count, "dubbele domeinen in de aanbevolen lijst")
        for domain in alle {
            XCTAssertTrue(
                WhitelistStore.isValidWhitelistDomain(domain),
                "ongeldig domein in de aanbevolen lijst: \(domain)"
            )
        }
        XCTAssertTrue(alle.contains("bandlab.com"))
    }

    func testMissingFiltersWhatIsAlreadyProtected() {
        let ontbreekt = RecommendedWhitelist.missing(from: ["bandlab.com", "https://GITHUB.com/login"])
        XCTAssertFalse(ontbreekt.contains("bandlab.com"))
        XCTAssertFalse(ontbreekt.contains("github.com"))
        XCTAssertTrue(ontbreekt.contains("suno.com"))
    }
}

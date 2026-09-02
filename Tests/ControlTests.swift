import XCTest
@testable import Crumb

final class DomainRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        domain: String = "shop.example",
        name: String = "prefs",
        browser: String = "Chrome",
        category: CookieCategory = .analytics,
        verdict: CookieVerdict = .reviewSuggested,
        protection: CookieProtection = .none,
        firstSeenDaysAgo: Double = 40
    ) -> CookieRecord {
        let firstSeen = now.addingTimeInterval(-firstSeenDaysAgo * 86_400)
        return CookieRecord(
            domain: domain, name: name, valueHash: "h", browser: browser, path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: firstSeen, lastSeen: firstSeen,
            category: category, verdict: verdict, reasoning: "", protection: protection
        )
    }

    func testAlwaysKeepWinsOverDeleteRule() {
        let rules = [
            DomainRule(domain: "shop.example", action: .alwaysKeep),
            DomainRule(domain: "shop.example", action: .deleteCookieName, cookieName: "prefs")
        ]
        let outcome = DomainRulesEngine.apply(rules, to: record(), now: now)
        XCTAssertTrue(outcome.protection?.isLocked == true)
        XCTAssertEqual(outcome.verdict, .keep, "bescherming wint altijd")
    }

    func testProtectCookieNameLocksMatchingCookieOnly() {
        let rules = [DomainRule(domain: "shop.example", action: .protectCookieName, cookieName: "session_id")]
        XCTAssertEqual(DomainRulesEngine.apply(rules, to: record(name: "session_id"), now: now).protection?.isLocked, true)
        XCTAssertNil(DomainRulesEngine.apply(rules, to: record(name: "prefs"), now: now).protection)
    }

    func testDeleteCookieNameForcesSafeToClean() {
        let rules = [DomainRule(domain: "shop.example", action: .deleteCookieName, cookieName: "prefs")]
        let outcome = DomainRulesEngine.apply(rules, to: record(name: "prefs", verdict: .keep), now: now)
        XCTAssertEqual(outcome.verdict, .safeToClean)
        XCTAssertTrue(outcome.reasoning?.contains("prefs") == true)

        // Geklemd cookie raakt een regel nooit.
        let locked = record(name: "prefs", protection: .locked("whitelist"))
        XCTAssertNil(DomainRulesEngine.apply(rules, to: locked, now: now).verdict)
    }

    func testCleanupOlderThanRespectsBoundaryAndVerdict() {
        let rules = [DomainRule(domain: "shop.example", action: .cleanupOlderThan, olderThanDays: 30)]
        XCTAssertEqual(DomainRulesEngine.apply(rules, to: record(firstSeenDaysAgo: 31), now: now).verdict, .safeToClean)
        XCTAssertNil(DomainRulesEngine.apply(rules, to: record(firstSeenDaysAgo: 10), now: now).verdict)
        // keep-verdict blijft keep — de regel forceert alleen bij bestaande kandidaten.
        XCTAssertNil(DomainRulesEngine.apply(rules, to: record(verdict: .keep, firstSeenDaysAgo: 31), now: now).verdict)
    }

    func testAlwaysTrackingMarksNonLockedCookies() {
        let rules = [DomainRule(domain: "shop.example", action: .alwaysTracking)]
        let outcome = DomainRulesEngine.apply(rules, to: record(category: .unknown, verdict: .keep), now: now)
        XCTAssertEqual(outcome.category, .marketingTracking)
        XCTAssertEqual(outcome.verdict, .reviewSuggested)

        let locked = record(protection: .locked("whitelist"))
        XCTAssertNil(DomainRulesEngine.apply(rules, to: locked, now: now).category)
    }

    func testBrowserFilterLimitsRuleScope() {
        let rules = [DomainRule(domain: "shop.example", action: .deleteCookieName, cookieName: "prefs", browser: "Firefox")]
        XCTAssertEqual(DomainRulesEngine.apply(rules, to: record(browser: "Firefox"), now: now).verdict, .safeToClean)
        XCTAssertNil(DomainRulesEngine.apply(rules, to: record(browser: "Chrome"), now: now).verdict)
    }

    func testSubdomainMatching() {
        let rules = [DomainRule(domain: "shop.example", action: .alwaysKeep)]
        XCTAssertTrue(DomainRulesEngine.matchingRules(for: record(domain: "cdn.shop.example"), rules: rules).count == 1)
        XCTAssertTrue(DomainRulesEngine.matchingRules(for: record(domain: "notshop.example"), rules: rules).isEmpty)
    }

    func testIntegrationThroughBuildRecords() async {
        SnapshotStore.overrideFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-rules-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: SnapshotStore.fileURL)
            SnapshotStore.overrideFileURL = nil
        }

        let raw = RawCookie(
            domain: "shop.example", name: "prefs", path: "/",
            expiry: Date(timeIntervalSince1970: 2_000_000_000),
            creation: now.addingTimeInterval(-100 * 86_400),
            isSecure: false, isHttpOnly: false, isSessionOnly: false,
            browser: "Chrome"
        )
        let records = await ScanService.buildRecords(
            rawCookies: [raw],
            whitelist: [],
            trackerList: TrackerList(suffixes: ["shop.example"]),
            now: now,
            domainRules: [DomainRule(domain: "shop.example", action: .cleanupOlderThan, olderThanDays: 30)]
        )
        XCTAssertEqual(records.first?.verdict, .safeToClean)
        XCTAssertTrue(records.first?.reasoning.contains("ouder dan 30 dagen") == true)

        // Zonder kandidaat-status (unknown/keep) raakt de regel het cookie niet.
        let unknown = RawCookie(
            domain: "plain.example", name: "prefs", path: "/",
            expiry: Date(timeIntervalSince1970: 2_000_000_000),
            creation: now.addingTimeInterval(-100 * 86_400),
            isSecure: false, isHttpOnly: false, isSessionOnly: false,
            browser: "Chrome"
        )
        let untouched = await ScanService.buildRecords(
            rawCookies: [unknown],
            whitelist: [],
            trackerList: TrackerList(suffixes: ["shop.example"]),
            now: now,
            domainRules: [DomainRule(domain: "plain.example", action: .cleanupOlderThan, olderThanDays: 30)]
        )
        XCTAssertEqual(untouched.first?.verdict, .keep)
    }
}

final class AutoCleanLimitsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(index: Int) -> CookieRecord {
        let firstSeen = now.addingTimeInterval(-100 * 86_400)
        return CookieRecord(
            domain: "ad\(index).example", name: "uid", valueHash: "h", browser: "Chrome", path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: firstSeen, lastSeen: firstSeen,
            category: .marketingTracking, verdict: .safeToClean, reasoning: "", protection: .none
        )
    }

    private func run(count: Int) -> ScanRun {
        ScanRun(startedAt: now, finishedAt: now, sources: [], records: (0..<count).map(record))
    }

    private var settings: AutoCleanSettings {
        AutoCleanSettings(enabled: true, includeMarketingTracking: true, includeAnalytics: false, minAgeDays: 30)
    }

    func testMaxPerRunCapsCandidates() {
        var limited = settings
        limited.maxPerRun = 5
        XCTAssertEqual(AutoCleanEngine.candidates(in: run(count: 12), settings: limited, now: now).count, 5)
    }

    func testThresholdSkipsSmallBatches() {
        var limited = settings
        limited.minSafeCookies = 20
        XCTAssertTrue(AutoCleanEngine.thresholdSkipped(candidates: AutoCleanEngine.candidates(in: run(count: 12), settings: limited, now: now), settings: limited))
        XCTAssertFalse(AutoCleanEngine.thresholdSkipped(candidates: AutoCleanEngine.candidates(in: run(count: 25), settings: limited, now: now), settings: limited))
        // Drempel 0 betekent: altijd door.
        XCTAssertFalse(AutoCleanEngine.thresholdSkipped(candidates: [], settings: settings))
    }

    func testDryRunPreviewEqualsCandidates() {
        // De dry-run preview is exact de kandidatenlijst — geen afwijkende logica.
        let candidates = AutoCleanEngine.candidates(in: run(count: 3), settings: settings, now: now)
        XCTAssertEqual(candidates.count, 3)
    }
}

final class AuditLogExportTests: XCTestCase {
    func testCSVContainsHeaderAndEscapedFields() throws {
        let entry = AuditEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mode: "manual", browser: "Chrome", domain: "a.com", name: "c,with-comma",
            path: "/", category: "unknown", verdict: "keep", reasoning: "r",
            result: "deleted", detail: "say \"hi\""
        )
        let csv = AuditLog.csv(entries: [entry])
        XCTAssertTrue(csv.hasPrefix("timestamp,mode,browser"))
        XCTAssertTrue(csv.contains("\"c,with-comma\""))
        XCTAssertTrue(csv.contains("\"say \"\"hi\"\"\""))
    }

    func testJSONExportRoundtrip() throws {
        let entry = AuditEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mode: "auto", browser: "Brave", domain: "b.com", name: "c",
            path: "/", category: "marketingTracking", verdict: "safeToClean", reasoning: "r",
            result: "deleted", detail: nil
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crumb-audit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try AuditLog.exportJSON(entries: [entry], to: url)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([AuditEntry].self, from: data)
        XCTAssertEqual(decoded.first?.domain, "b.com")
    }
}

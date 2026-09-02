import XCTest
@testable import Crumb

final class RecommendationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        domain: String = "ad.example",
        name: String = "uid",
        category: CookieCategory = .marketingTracking,
        verdict: CookieVerdict,
        protection: CookieProtection = .none,
        firstSeenDaysAgo: Double = 0
    ) -> CookieRecord {
        let firstSeen = now.addingTimeInterval(-firstSeenDaysAgo * 86_400)
        return CookieRecord(
            domain: domain, name: name, valueHash: "h", browser: "Chrome", path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: firstSeen, lastSeen: firstSeen,
            category: category, verdict: verdict, reasoning: "", protection: protection
        )
    }

    private func run(records: [CookieRecord]) -> ScanRun {
        ScanRun(startedAt: now, finishedAt: now, sources: [], records: records)
    }

    func testSafeToCleanRecommendationHasHighestImpact() {
        let recs = RecommendationEngine.recommendations(
            for: run(records: [
                record(verdict: .safeToClean),
                record(name: "uid2", verdict: .safeToClean, firstSeenDaysAgo: 100)
            ]),
            now: now
        )

        XCTAssertEqual(recs.first?.kind, .safeToClean)
        XCTAssertEqual(recs.first?.recordCount, 2)
        XCTAssertTrue(recs.first?.title.contains("2 cookies") == true)
    }

    func testStaleCookieRecommendation() {
        let recs = RecommendationEngine.recommendations(
            for: run(records: [
                record(name: "old_review", verdict: .reviewSuggested, firstSeenDaysAgo: 100),
                record(name: "old_keep", category: .unknown, verdict: .keep, firstSeenDaysAgo: 100),
                record(name: "young", verdict: .reviewSuggested, firstSeenDaysAgo: 5)
            ]),
            now: now
        )

        let stale = recs.first { $0.kind == .staleCookies }
        XCTAssertEqual(stale?.recordCount, 1)
        XCTAssertTrue(stale?.title.contains("ouder dan 90 dagen") == true)
    }

    func testReappearingTrackersNeedHistoryAgreement() {
        let pastRun = ScanRun(
            startedAt: now.addingTimeInterval(-7 * 86_400),
            finishedAt: now.addingTimeInterval(-7 * 86_400),
            sources: [],
            records: [record(domain: "sticky.net", verdict: .reviewSuggested)]
        )
        let history = [pastRun, pastRun, pastRun]

        let recs = RecommendationEngine.recommendations(
            for: run(records: [
                record(domain: "sticky.net", verdict: .reviewSuggested),
                record(domain: "other.net", verdict: .reviewSuggested)
            ]),
            history: history,
            now: now
        )

        let reappearing = recs.first { $0.kind == .reappearingTrackers }
        XCTAssertEqual(reappearing?.recordCount, 1)
        XCTAssertTrue(reappearing?.detail.contains("sticky.net") == true)
        XCTAssertNil(recs.first { $0.kind == .topDomains }, "met 2 tracking-cookies geen topdomeinen-advies")
    }

    func testTopDomainsCoversSeventyPercent() {
        var records: [CookieRecord] = []
        for i in 0..<8 {
            records.append(record(domain: "big\(i < 4 ? "1" : "2").net", name: "c\(i)", verdict: .reviewSuggested))
        }
        let recs = RecommendationEngine.recommendations(for: run(records: records), now: now)

        let top = recs.first { $0.kind == .topDomains }
        XCTAssertNotNil(top)
        XCTAssertTrue(top!.title.contains("2 domeinen veroorzaken 100%"))
    }

    func testEmptyRunHasNoRecommendations() {
        XCTAssertTrue(RecommendationEngine.recommendations(for: run(records: []), now: now).isEmpty)
    }

    func testLockedCookiesNeverRecommended() {
        let recs = RecommendationEngine.recommendations(
            for: run(records: [
                record(name: "locked", verdict: .safeToClean, protection: .locked("whitelist"), firstSeenDaysAgo: 100)
            ]),
            now: now
        )
        XCTAssertTrue(recs.isEmpty)
    }
}

final class ProtectionExplanationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        category: CookieCategory = .marketingTracking,
        verdict: CookieVerdict,
        protection: CookieProtection = .none,
        reasoning: String = "",
        firstSeenDaysAgo: Double = 40
    ) -> CookieRecord {
        let firstSeen = now.addingTimeInterval(-firstSeenDaysAgo * 86_400)
        return CookieRecord(
            domain: "ad.example", name: "uid", valueHash: "h", browser: "Chrome", path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: firstSeen, lastSeen: firstSeen,
            category: category, verdict: verdict, reasoning: reasoning, protection: protection
        )
    }

    func testLockedExplainsAuthToken() {
        let explanation = ProtectionExplanation.explain(
            record(verdict: .keep, protection: .locked("Naam bevat auth-token ('session') — sessiecookie.")),
            now: now
        )
        XCTAssertEqual(explanation, "Beschermd: naam bevat 'session'")
    }

    func testLockedExplainsWhitelist() {
        let explanation = ProtectionExplanation.explain(
            record(verdict: .keep, protection: .locked("Staat op de gebruikerswhitelist ('bank.nl') — nooit wissen.")),
            now: now
        )
        XCTAssertEqual(explanation, "Beschermd: staat op je whitelist")
    }

    func testLockedExplainsManualProtection() {
        let explanation = ProtectionExplanation.explain(
            record(verdict: .keep, protection: .locked("Handmatig beschermd door de gebruiker — nooit wissen.")),
            now: now
        )
        XCTAssertEqual(explanation, "Beschermd: handmatig beschermd door jou")
    }

    func testReviewOnlyExplainsActiveSession() {
        let explanation = ProtectionExplanation.explain(
            record(verdict: .reviewSuggested, protection: .reviewOnly("Beveiligde cookie minder dan 24 uur geleden aangemaakt — mogelijk actieve sessie.")),
            now: now
        )
        XCTAssertEqual(explanation, "Review vereist: secure + httpOnly + jonger dan 24 uur — mogelijk actieve sessie")
    }

    func testSafeToCleanExplainsWhy() {
        let explanation = ProtectionExplanation.explain(record(verdict: .safeToClean), now: now)
        XCTAssertEqual(explanation, "Verwijderbaar: tracker, ouder dan 30 dagen, geen bescherming")
    }

    func testDisagreementExplainsDowngrade() {
        let explanation = ProtectionExplanation.explain(
            record(category: .marketingTracking, verdict: .reviewSuggested, reasoning: "AI adviseert opschonen, maar de regel-laag kan dit niet bevestigen (categorie 'Onbekend', advies 'Bewaren') — afgezet naar review. AI: test"),
            now: now
        )
        XCTAssertEqual(explanation, "Niet verwijderd: AI en regellaag zijn het niet eens — beoordeel handmatig.")
    }
}

final class ProtectedCookieStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ProtectedCookieStore.overrideFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-protected-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: ProtectedCookieStore.fileURL)
        ProtectedCookieStore.overrideFileURL = nil
        super.tearDown()
    }

    func testAddRemoveRoundtrip() throws {
        var store = ProtectedCookieStore()
        store.add(domain: "example.com", name: "prefs", path: "/")
        XCTAssertTrue(store.contains(domain: "example.com", name: "prefs", path: "/"))
        XCTAssertFalse(store.contains(domain: "example.com", name: "other", path: "/"))

        try store.save()
        var loaded = ProtectedCookieStore.load()
        XCTAssertTrue(loaded.contains(domain: "example.com", name: "prefs", path: "/"))

        loaded.remove(domain: "example.com", name: "prefs", path: "/")
        try loaded.save()
        XCTAssertFalse(ProtectedCookieStore.load().contains(domain: "example.com", name: "prefs", path: "/"))
    }

    func testProtectedCookieIsLockedBySafelistEngine() {
        var store = ProtectedCookieStore()
        store.add(domain: "example.com", name: "prefs", path: "/")

        let engine = SafelistEngine(whitelist: [], protectedCookies: Set(store.keys))
        let protection = engine.evaluate(
            domain: "example.com", name: "prefs",
            isSecure: false, isHttpOnly: false, isSessionOnly: false,
            creation: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 1_000_000_000)
        )
        XCTAssertEqual(protection.isLocked, true)

        // Andere cookie op hetzelfde domein blijft onbeschermd.
        let other = engine.evaluate(
            domain: "example.com", name: "other",
            isSecure: false, isHttpOnly: false, isSessionOnly: false,
            creation: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 1_000_000_000)
        )
        XCTAssertEqual(other, .none)
    }
}

import XCTest
@testable import Crumb

final class InsightsEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        domain: String,
        name: String = "uid",
        browser: String = "Chrome",
        category: CookieCategory = .marketingTracking,
        churn: Int? = nil
    ) -> CookieRecord {
        CookieRecord(
            domain: domain, name: name, valueHash: "h", browser: browser, path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: now, lastSeen: now,
            category: category, verdict: .reviewSuggested, reasoning: "", protection: .none,
            valueChurn: churn
        )
    }

    private func run(records: [CookieRecord], minutesAgo: Int = 0) -> ScanRun {
        let date = now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
        return ScanRun(startedAt: date, finishedAt: date, sources: [], records: records)
    }

    // MARK: Diff

    func testDiffDetectsNewAndDisappeared() {
        let prior = run(records: [
            record(domain: "a.com"),
            record(domain: "b.com", name: "gone")
        ], minutesAgo: 60)
        let current = run(records: [
            record(domain: "a.com"),
            record(domain: "c.com", name: "fresh")
        ])

        let diff = InsightsEngine.diff(current: current, prior: prior)
        XCTAssertEqual(diff.newCookies.map(\.domain), ["c.com"])
        XCTAssertEqual(diff.disappearedCookies.map(\.name), ["gone"])
    }

    func testDiffIsBrowserAgnostic() {
        // Zelfde cookie in een andere browser is geen "nieuw"/"verdwijnen".
        let prior = run(records: [record(domain: "a.com", browser: "Chrome")], minutesAgo: 60)
        let current = run(records: [record(domain: "a.com", browser: "Brave")])
        let diff = InsightsEngine.diff(current: current, prior: prior)
        XCTAssertTrue(diff.newCookies.isEmpty)
        XCTAssertTrue(diff.disappearedCookies.isEmpty)
    }

    // MARK: Browservergelijking

    func testBrowserSharingGroupsDuplicates() {
        let testRun = run(records: [
            record(domain: "tracker.net", browser: "Chrome"),
            record(domain: "tracker.net", browser: "Brave"),
            record(domain: "tracker.net", browser: "Safari"),
            record(domain: "site.com", browser: "Chrome", category: .functional)
        ])

        let sharing = InsightsEngine.browserSharing(in: testRun)
        XCTAssertEqual(sharing.first?.domain, "tracker.net")
        XCTAssertEqual(sharing.first?.browserCount, 3)
        XCTAssertTrue(sharing.first?.isTracking == true)

        let inAll = InsightsEngine.trackingInAllBrowsers(in: testRun)
        XCTAssertEqual(inAll.map(\.domain), ["tracker.net"])
    }

    func testTrackingInAllBrowsersRequiresMultipleBrowsers() {
        let singleBrowserRun = run(records: [
            record(domain: "tracker.net", browser: "Chrome"),
            record(domain: "tracker.net", browser: "Chrome")
        ])
        XCTAssertTrue(InsightsEngine.trackingInAllBrowsers(in: singleBrowserRun).isEmpty)
    }

    // MARK: Churn

    func testTopChurnSortsDescending() {
        let testRun = run(records: [
            record(domain: "low.net", churn: 1),
            record(domain: "high.net", churn: 7),
            record(domain: "none.net", churn: nil)
        ])
        XCTAssertEqual(InsightsEngine.topChurn(in: testRun).map(\.domain), ["high.net", "low.net"])
    }

    // MARK: Persistentie

    func testMostPersistentTrackingDomainsCountsRuns() {
        let a = run(records: [record(domain: "sticky.net")], minutesAgo: 30)
        let b = run(records: [record(domain: "sticky.net")], minutesAgo: 20)
        let c = run(records: [record(domain: "other.net")], minutesAgo: 10)
        let persistent = InsightsEngine.mostPersistentTrackingDomains(runs: [a, b, c])
        XCTAssertEqual(persistent.first?.domain, "sticky.net")
        XCTAssertEqual(persistent.first?.runs, 2)
    }

    // MARK: Privacy-score

    func testPrivacyScoreHighWithCleanProfile() {
        let cleanRun = run(records: [
            record(domain: "site.com", category: .essential),
            record(domain: "site.com", category: .functional)
        ])
        let score = InsightsEngine.privacyScore(for: cleanRun)
        XCTAssertEqual(score.score, 100)
        XCTAssertEqual(score.label, "Goed beschermd")
    }

    func testPrivacyScoreLowWithHeavyTracking() {
        let heavyRun = run(records: [
            record(domain: "t0.net"),
            record(domain: "t1.net"),
            record(domain: "t2.net"),
            record(domain: "t3.net", category: .unknown)
        ])
        let score = InsightsEngine.privacyScore(for: heavyRun)
        XCTAssertLessThan(score.score, 60)
        XCTAssertEqual(score.label, "Aandacht nodig")
    }

    func testPrivacyScoreTracksDeltaAgainstPriorRun() {
        let prior = run(records: (0..<10).map { record(domain: "t\($0).net") }, minutesAgo: 60)
        let current = run(records: (0..<7).map { record(domain: "t\($0).net") })
        let score = InsightsEngine.privacyScore(for: current, priorRuns: [prior])
        XCTAssertEqual(score.trackingDelta, -3)
        XCTAssertEqual(score.trackingDeltaPercent, -30.0)
        XCTAssertTrue(score.explanation.contains("gedaald"))
    }

    func testPrivacyScoreEmptyRun() {
        let score = InsightsEngine.privacyScore(for: run(records: []))
        XCTAssertEqual(score.score, 100)
        XCTAssertEqual(score.label, "Geen cookies")
    }
}

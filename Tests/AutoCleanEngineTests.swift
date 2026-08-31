import XCTest
@testable import Crumb

final class AutoCleanEngineTests: XCTestCase {
    private func record(
        category: CookieCategory,
        verdict: CookieVerdict,
        protection: CookieProtection = .none,
        firstSeen: Date
    ) -> CookieRecord {
        CookieRecord(
            domain: "ad.example",
            name: "uid",
            valueHash: "abc",
            browser: "Chrome",
            path: "/",
            expiry: nil,
            isSecure: false,
            isHttpOnly: false,
            isSessionOnly: false,
            firstSeen: firstSeen,
            lastSeen: firstSeen,
            category: category,
            verdict: verdict,
            reasoning: "",
            protection: protection
        )
    }

    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func settings(
        enabled: Bool = true,
        marketing: Bool = true,
        analytics: Bool = false,
        minAgeDays: Int = 30
    ) -> AutoCleanSettings {
        AutoCleanSettings(
            enabled: enabled,
            includeMarketingTracking: marketing,
            includeAnalytics: analytics,
            minAgeDays: minAgeDays
        )
    }

    private func run(records: [CookieRecord]) -> ScanRun {
        ScanRun(startedAt: now, finishedAt: now, sources: [], records: records)
    }

    func testDisabledSettingsYieldNoCandidates() {
        let record = record(
            category: .marketingTracking,
            verdict: .safeToClean,
            firstSeen: now.addingTimeInterval(-90 * 86_400)
        )
        XCTAssertTrue(AutoCleanEngine.candidates(in: run(records: [record]), settings: settings(enabled: false), now: now).isEmpty)
    }

    func testMarketingTrackingOldEnoughIsCandidate() {
        let record = record(
            category: .marketingTracking,
            verdict: .safeToClean,
            firstSeen: now.addingTimeInterval(-40 * 86_400)
        )
        XCTAssertEqual(AutoCleanEngine.candidates(in: run(records: [record]), settings: settings(), now: now).count, 1)
    }

    func testTooYoungIsNotCandidate() {
        let record = record(
            category: .marketingTracking,
            verdict: .safeToClean,
            firstSeen: now.addingTimeInterval(-5 * 86_400)
        )
        XCTAssertTrue(AutoCleanEngine.candidates(in: run(records: [record]), settings: settings(), now: now).isEmpty)
    }

    func testAnalyticsRequiresOptIn() {
        let record = record(
            category: .analytics,
            verdict: .safeToClean,
            firstSeen: now.addingTimeInterval(-90 * 86_400)
        )
        XCTAssertTrue(AutoCleanEngine.candidates(in: run(records: [record]), settings: settings(marketing: true, analytics: false), now: now).isEmpty)
        XCTAssertEqual(AutoCleanEngine.candidates(in: run(records: [record]), settings: settings(marketing: true, analytics: true), now: now).count, 1)
    }

    func testSafelistedNeverCandidate() {
        let record = record(
            category: .marketingTracking,
            verdict: .safeToClean,
            protection: .locked("whitelist"),
            firstSeen: now.addingTimeInterval(-90 * 86_400)
        )
        XCTAssertTrue(AutoCleanEngine.candidates(in: run(records: [record]), settings: settings(), now: now).isEmpty)
    }

    func testReviewVerdictNeverCandidate() {
        let record = record(
            category: .marketingTracking,
            verdict: .reviewSuggested,
            firstSeen: now.addingTimeInterval(-90 * 86_400)
        )
        XCTAssertTrue(AutoCleanEngine.candidates(in: run(records: [record]), settings: settings(), now: now).isEmpty)
    }
}

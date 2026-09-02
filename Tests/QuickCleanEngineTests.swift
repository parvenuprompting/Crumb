import XCTest
@testable import Crumb

final class QuickCleanEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecord(
        domain: String = "example.com",
        name: String = "cookie",
        category: CookieCategory,
        verdict: CookieVerdict,
        protection: CookieProtection = .none,
        firstSeenDaysAgo: Double = 0,
        isSecure: Bool = false,
        isHttpOnly: Bool = false,
        isSessionOnly: Bool = false,
        expiry: Date? = nil
    ) -> CookieRecord {
        let firstSeen = now.addingTimeInterval(-firstSeenDaysAgo * 86_400)
        return CookieRecord(
            domain: domain,
            name: name,
            valueHash: "hash",
            browser: "Chrome",
            path: "/",
            expiry: expiry,
            isSecure: isSecure,
            isHttpOnly: isHttpOnly,
            isSessionOnly: isSessionOnly,
            firstSeen: firstSeen,
            lastSeen: firstSeen,
            category: category,
            verdict: verdict,
            reasoning: "test",
            protection: protection
        )
    }

    private func makeRun(records: [CookieRecord]) -> ScanRun {
        ScanRun(startedAt: now, finishedAt: now, sources: [], records: records)
    }

    func testMarketingTrackingPresetSelectsOnlyMarketing() {
        let m1 = makeRecord(name: "tracker1", category: .marketingTracking, verdict: .reviewSuggested)
        let m2 = makeRecord(name: "tracker2", category: .marketingTracking, verdict: .safeToClean)
        let f1 = makeRecord(name: "pref", category: .functional, verdict: .keep)
        let run = makeRun(records: [m1, m2, f1])

        let candidates = QuickCleanEngine.candidates(for: .marketingTracking, in: run, now: now)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map(\.name), ["tracker1", "tracker2"])
    }

    func testStaleAnalyticsPresetRespects30DayBoundary() {
        let oldAnalytics = makeRecord(name: "ga_old", category: .analytics, verdict: .reviewSuggested, firstSeenDaysAgo: 31)
        let exactBoundary = makeRecord(name: "ga_exact", category: .analytics, verdict: .reviewSuggested, firstSeenDaysAgo: 30)
        let recentAnalytics = makeRecord(name: "ga_recent", category: .analytics, verdict: .keep, firstSeenDaysAgo: 29)
        let run = makeRun(records: [oldAnalytics, exactBoundary, recentAnalytics])

        let candidates = QuickCleanEngine.candidates(for: .staleAnalytics, in: run, now: now)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map(\.name), ["ga_old", "ga_exact"])
    }

    func testAllSafeToCleanPresetSelectsOnlySafeVerdict() {
        let safe1 = makeRecord(name: "c1", category: .marketingTracking, verdict: .safeToClean)
        let safe2 = makeRecord(name: "c2", category: .analytics, verdict: .safeToClean)
        let review = makeRecord(name: "c3", category: .marketingTracking, verdict: .reviewSuggested)
        let run = makeRun(records: [safe1, safe2, review])

        let candidates = QuickCleanEngine.candidates(for: .allSafeToClean, in: run, now: now)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map(\.name), ["c1", "c2"])
    }

    func testUnclassifiedPresetSelectsExpiredAndSessionCookies() {
        let expiredUnknown = makeRecord(
            name: "old_unknown",
            category: .unknown,
            verdict: .keep,
            expiry: now.addingTimeInterval(-86_400)
        )
        let sessionUnknown = makeRecord(
            name: "session_unknown",
            category: .unknown,
            verdict: .keep,
            isSessionOnly: true
        )
        let expiredThirdParty = makeRecord(
            name: "expired_tp",
            category: .thirdPartyUnknown,
            verdict: .keep,
            expiry: now.addingTimeInterval(-3_600)
        )
        let run = makeRun(records: [expiredUnknown, sessionUnknown, expiredThirdParty])

        let candidates = QuickCleanEngine.candidates(for: .unclassifiedNonEssential, in: run, now: now)
        XCTAssertEqual(candidates.map(\.name).sorted(), ["expired_tp", "old_unknown", "session_unknown"])
    }

    func testUnclassifiedPresetRejectsActiveAndSecureCookies() {
        let futureExpiry = makeRecord(
            name: "active_unknown",
            category: .unknown,
            verdict: .keep,
            expiry: now.addingTimeInterval(30 * 86_400)
        )
        let secureSession = makeRecord(
            name: "secure_unknown",
            category: .unknown,
            verdict: .keep,
            isSecure: true,
            isHttpOnly: true,
            expiry: now.addingTimeInterval(-86_400)
        )
        let tracked = makeRecord(
            name: "tracker",
            category: .marketingTracking,
            verdict: .reviewSuggested,
            expiry: now.addingTimeInterval(-86_400)
        )
        let locked = makeRecord(
            name: "locked_unknown",
            category: .unknown,
            verdict: .keep,
            protection: .locked("whitelist"),
            expiry: now.addingTimeInterval(-86_400)
        )
        let run = makeRun(records: [futureExpiry, secureSession, tracked, locked])

        XCTAssertTrue(QuickCleanEngine.candidates(for: .unclassifiedNonEssential, in: run, now: now).isEmpty)
    }

    func testSafelistLockedCookiesAreNeverCandidates() {
        let lockedMarketing = makeRecord(
            name: "locked_tracker",
            category: .marketingTracking,
            verdict: .safeToClean,
            protection: .locked("Safelist auth pattern")
        )
        let lockedSafe = makeRecord(
            name: "locked_safe",
            category: .analytics,
            verdict: .safeToClean,
            protection: .locked("User whitelist")
        )
        let unlockedMarketing = makeRecord(
            name: "free_tracker",
            category: .marketingTracking,
            verdict: .safeToClean,
            protection: .none
        )
        let run = makeRun(records: [lockedMarketing, lockedSafe, unlockedMarketing])

        for preset in QuickCleanPreset.allCases {
            let candidates = QuickCleanEngine.candidates(for: preset, in: run, now: now)
            XCTAssertFalse(candidates.contains(where: { $0.protection.isLocked }))
        }
    }
}

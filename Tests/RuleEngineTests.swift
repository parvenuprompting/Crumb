import XCTest
@testable import Crumb

final class RuleEngineTests: XCTestCase {
    private let trackerList = TrackerList(suffixes: ["adnxs.com", "doubleclick.net"])
    private var engine: RuleEngine {
        RuleEngine(trackerList: trackerList, now: Date(timeIntervalSince1970: 1_000_000_000))
    }

    private func raw(
        domain: String = "example.com",
        name: String = "prefs",
        isSecure: Bool = false,
        isHttpOnly: Bool = false,
        isSessionOnly: Bool = false,
        creation: Date? = nil
    ) -> RawCookie {
        RawCookie(
            domain: domain,
            name: name,
            path: "/",
            expiry: isSessionOnly ? nil : Date(timeIntervalSince1970: 2_000_000_000),
            creation: creation,
            isSecure: isSecure,
            isHttpOnly: isHttpOnly,
            isSessionOnly: isSessionOnly
        )
    }

    func testTrackerDomainIsMarketingTrackingAndReview() {
        let result = engine.classify(raw: raw(domain: "cdn.adnxs.com", name: "uuid2"), protection: .none)
        XCTAssertEqual(result.category, .marketingTracking)
        XCTAssertEqual(result.verdict, .reviewSuggested)
    }

    func testAnalyticsNameRecentIsKept() {
        let creation = Date(timeIntervalSince1970: 999_000_000)
        let result = engine.classify(raw: raw(name: "_ga", creation: creation), protection: .none)
        XCTAssertEqual(result.category, .analytics)
        XCTAssertEqual(result.verdict, .keep)
    }

    func testAnalyticsNameOlderThan30DaysIsReview() {
        let creation = Date(timeIntervalSince1970: 1_000_000_000 - 40 * 24 * 60 * 60)
        let result = engine.classify(raw: raw(name: "_ga", creation: creation), protection: .none)
        XCTAssertEqual(result.category, .analytics)
        XCTAssertEqual(result.verdict, .reviewSuggested)
    }

    func testSecureHttpOnlyPersistentUnknownIsFunctional() {
        let result = engine.classify(
            raw: raw(isSecure: true, isHttpOnly: true),
            protection: .none
        )
        XCTAssertEqual(result.category, .functional)
        XCTAssertEqual(result.verdict, .keep)
    }

    func testUnclassifiedGoesToUnknownAndKeeps() {
        let result = engine.classify(raw: raw(name: "some_cookie"), protection: .none)
        XCTAssertEqual(result.category, .unknown)
        XCTAssertEqual(result.verdict, .keep)
    }

    func testLockedProtectionOverridesTrackerClassification() {
        let result = engine.classify(
            raw: raw(domain: "adnxs.com", name: "uuid2"),
            protection: .locked("Staat op de gebruikerswhitelist ('adnxs.com') — nooit wissen.")
        )
        XCTAssertEqual(result.category, .essential)
        XCTAssertEqual(result.verdict, .keep)
    }

    func testReviewOnlyProtectionCapsAtReviewSuggested() {
        let creation = Date(timeIntervalSince1970: 1_000_000_000 - 3600)
        let result = engine.classify(
            raw: raw(isSecure: true, isHttpOnly: true, creation: creation),
            protection: .reviewOnly("mogelijk actieve sessie")
        )
        XCTAssertEqual(result.verdict, .reviewSuggested)
    }

    func testTrackerListSuffixMatching() {
        XCTAssertTrue(trackerList.isTracker(domain: "adnxs.com"))
        XCTAssertTrue(trackerList.isTracker(domain: "a.b.adnxs.com"))
        XCTAssertTrue(trackerList.isTracker(domain: "doubleclick.NET"))
        XCTAssertFalse(trackerList.isTracker(domain: "notadnxs.com"))
        XCTAssertFalse(trackerList.isTracker(domain: "example.com"))
    }

    func testAnalyticsNameDetection() {
        XCTAssertTrue(RuleEngine.isAnalyticsName("_ga"))
        XCTAssertTrue(RuleEngine.isAnalyticsName("_ga_XXXXXX"))
        XCTAssertTrue(RuleEngine.isAnalyticsName("mp_abc123"))
        XCTAssertFalse(RuleEngine.isAnalyticsName("preferences"))
    }
}

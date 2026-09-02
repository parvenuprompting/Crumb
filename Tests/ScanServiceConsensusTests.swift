import XCTest
@testable import Crumb

/// Integratietests: de dubbele goedkeuring door de volledige
/// buildRecords-pipeline (regellaag + safelist + AI-consensus).
final class ScanServiceConsensusTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotStore.overrideFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-consensus-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: SnapshotStore.fileURL)
        SnapshotStore.overrideFileURL = nil
        super.tearDown()
    }

    private func raw(
        domain: String,
        aiCategory: CookieCategory?,
        aiVerdict: LLMVerdict?
    ) -> RawCookie {
        RawCookie(
            domain: domain, name: "prefs", path: "/",
            expiry: Date(timeIntervalSince1970: 2_000_000_000),
            creation: Date(timeIntervalSince1970: 1_000_000_000),
            isSecure: false, isHttpOnly: false, isSessionOnly: false,
            browser: "Chrome",
            aiCategory: aiCategory, aiVerdict: aiVerdict, aiReasoning: "test"
        )
    }

    func testRuleLayerCandidatePlusAISafeYieldsSafeToClean() async {
        let records = await ScanService.buildRecords(
            rawCookies: [raw(domain: "adnxs.com", aiCategory: .marketingTracking, aiVerdict: .safe)],
            whitelist: [],
            trackerList: TrackerList(suffixes: ["adnxs.com"]),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(records.first?.category, .marketingTracking)
        XCTAssertEqual(records.first?.verdict, .safeToClean)
        XCTAssertTrue(records.first?.reasoning.contains("beide") == true)
    }

    func testAIAloneIsDowngradedToReview() async {
        // De regel-laag ziet geen tracker (domein onbekend): AI-alleen mag
        // nooit safeToClean opleveren — de dubbele goedkeuring.
        let records = await ScanService.buildRecords(
            rawCookies: [raw(domain: "opaque.example", aiCategory: .marketingTracking, aiVerdict: .safe)],
            whitelist: [],
            trackerList: TrackerList(suffixes: ["adnxs.com"]),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(records.first?.category, .marketingTracking)
        XCTAssertEqual(records.first?.verdict, .reviewSuggested)
    }

    func testWhitelistedCookieIsNeverJudgedOrCleaned() async {
        let records = await ScanService.buildRecords(
            rawCookies: [raw(domain: "adnxs.com", aiCategory: .marketingTracking, aiVerdict: .safe)],
            whitelist: ["adnxs.com"],
            trackerList: TrackerList(suffixes: ["adnxs.com"]),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(records.first?.protection.isLocked == true)
        XCTAssertEqual(records.first?.verdict, .keep)
    }

    func testAIKeepOnTrackerStaysKeep() async {
        let records = await ScanService.buildRecords(
            rawCookies: [raw(domain: "adnxs.com", aiCategory: .marketingTracking, aiVerdict: .keep)],
            whitelist: [],
            trackerList: TrackerList(suffixes: ["adnxs.com"]),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(records.first?.verdict, .keep)
    }
}

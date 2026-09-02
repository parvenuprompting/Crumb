import XCTest
@testable import Crumb

final class ChurnDetectionTests: XCTestCase {
    private var tempSnapshotURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-snapshot-\(UUID().uuidString).json")
    }

    override func tearDown() {
        SnapshotStore.overrideFileURL = nil
        super.tearDown()
    }

    private func raw(
        valueHash: String?,
        browser: String = "Chrome"
    ) -> RawCookie {
        RawCookie(
            domain: "ads.example",
            name: "uid",
            path: "/",
            expiry: Date(timeIntervalSince1970: 2_000_000_000),
            creation: Date(timeIntervalSince1970: 1_000_000_000),
            isSecure: false,
            isHttpOnly: false,
            isSessionOnly: false,
            browser: browser,
            valueHash: valueHash
        )
    }

    private func buildRecords(_ cookies: [RawCookie], now: Date) async -> [CookieRecord] {
        await ScanService.buildRecords(
            rawCookies: cookies,
            whitelist: [],
            trackerList: TrackerList(suffixes: []),
            now: now
        )
    }

    func testChurnIncrementsOnlyOnValueChange() async {
        SnapshotStore.overrideFileURL = tempSnapshotURL
        defer { try? FileManager.default.removeItem(at: SnapshotStore.fileURL) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Run 1: eerste waarneming, geen churn.
        var records = await buildRecords([raw(valueHash: "aaaa")], now: now)
        XCTAssertEqual(records.first?.valueChurn, nil)

        // Run 2: zelfde waarde, geen churn.
        records = await buildRecords([raw(valueHash: "aaaa")], now: now.addingTimeInterval(3600))
        XCTAssertEqual(records.first?.valueChurn, nil)

        // Run 3: nieuwe waarde → churn 1.
        records = await buildRecords([raw(valueHash: "bbbb")], now: now.addingTimeInterval(7200))
        XCTAssertEqual(records.first?.valueChurn, 1)

        // Run 4: opnieuw nieuwe waarde → churn 2.
        records = await buildRecords([raw(valueHash: "cccc")], now: now.addingTimeInterval(10_800))
        XCTAssertEqual(records.first?.valueChurn, 2)
    }

    func testChurnIsTrackedPerBrowser() async {
        SnapshotStore.overrideFileURL = tempSnapshotURL
        defer { try? FileManager.default.removeItem(at: SnapshotStore.fileURL) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Eerste waarneming in beide browsers.
        _ = await buildRecords([
            raw(valueHash: "aaaa", browser: "Chrome"),
            raw(valueHash: "bbbb", browser: "Brave")
        ], now: now)

        // Alleen Chrome verandert: churn 1 voor Chrome, geen churn voor Brave.
        let records = await buildRecords([
            raw(valueHash: "zzzz", browser: "Chrome"),
            raw(valueHash: "bbbb", browser: "Brave")
        ], now: now.addingTimeInterval(3600))

        let chrome = records.first { $0.browser == "Chrome" }
        let brave = records.first { $0.browser == "Brave" }
        XCTAssertEqual(chrome?.valueChurn, 1)
        XCTAssertEqual(brave?.valueChurn, nil)
    }

    func testCookieWithoutValueHashFallsBackToIdentityHash() async {
        SnapshotStore.overrideFileURL = tempSnapshotURL
        defer { try? FileManager.default.removeItem(at: SnapshotStore.fileURL) }

        let records = await buildRecords([raw(valueHash: nil)], now: Date(timeIntervalSince1970: 1_700_000_000))
        let record = try? XCTUnwrap(records.first)
        XCTAssertEqual(record?.valueHash, Hashing.cookieValueHash(domain: "ads.example", name: "uid", path: "/"))
        XCTAssertEqual(record?.valueChurn, nil)
    }

    func testSnapshotDecodesWithoutNewFields() throws {
        // Oude snapshot.json (zonder lastValueHashes/churnCount) moet blijven laden.
        let old = SnapshotStore(entries: [
            "a.com|c|/": SnapshotEntry(
                firstSeen: Date(timeIntervalSince1970: 100),
                lastSeen: Date(timeIntervalSince1970: 200)
            )
        ])
        let data = try JSONEncoder().encode(old)

        SnapshotStore.overrideFileURL = tempSnapshotURL
        defer { try? FileManager.default.removeItem(at: SnapshotStore.fileURL) }
        try data.write(to: SnapshotStore.fileURL)

        let loaded = SnapshotStore.load()
        XCTAssertEqual(loaded.entries["a.com|c|/"]?.firstSeen, Date(timeIntervalSince1970: 100))
        XCTAssertNil(loaded.entries["a.com|c|/"]?.churnCounts)
        XCTAssertNil(loaded.entries["a.com|c|/"]?.lastValueHashes)
    }

    func testCookieRecordDecodesWithoutValueChurn() throws {
        // Oude run-rapporten (zonder valueChurn) moeten blijven decoden.
        let record = CookieRecord(
            domain: "a.com", name: "c", valueHash: "x", browser: "Chrome", path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: Date(timeIntervalSince1970: 1), lastSeen: Date(timeIntervalSince1970: 2),
            category: .unknown, verdict: .keep, reasoning: "", protection: .none
        )
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        object.removeValue(forKey: "valueChurn")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CookieRecord.self, from: stripped)
        XCTAssertEqual(decoded.valueChurn, nil)
        XCTAssertEqual(decoded.domain, "a.com")
    }
}

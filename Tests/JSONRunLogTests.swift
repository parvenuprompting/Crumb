import XCTest
@testable import Crumb

final class JSONRunLogTests: XCTestCase {
    private var testDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-runlog-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        JSONRunLog.overrideDirectory = nil
        super.tearDown()
    }

    private func makeRun(startedAt: Date) -> ScanRun {
        ScanRun(startedAt: startedAt, finishedAt: startedAt.addingTimeInterval(1), sources: [], records: [])
    }

    func testTwoWritesWithinSameSecondDoNotCollide() throws {
        let dir = testDirectory
        JSONRunLog.overrideDirectory = dir
        defer { try? FileManager.default.removeItem(at: dir) }

        // Regressie: zonder milliseconden overschreven twee runs binnen
        // dezelfde seconde elkaars rapport.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let url1 = try JSONRunLog.write(run: makeRun(startedAt: base))
        let url2 = try JSONRunLog.write(run: makeRun(startedAt: base.addingTimeInterval(0.25)))

        XCTAssertNotEqual(url1, url2)
        XCTAssertEqual(JSONRunLog.allRuns(limit: 10).count, 2)
    }

    func testWriteRoundTripAndLastRun() throws {
        let dir = testDirectory
        JSONRunLog.overrideDirectory = dir
        defer { try? FileManager.default.removeItem(at: dir) }

        let older = try JSONRunLog.write(run: makeRun(startedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let newer = try JSONRunLog.write(run: makeRun(startedAt: Date(timeIntervalSince1970: 1_700_000_100)))

        XCTAssertNotEqual(older, newer)
        XCTAssertEqual(JSONRunLog.lastRun()?.startedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }
}

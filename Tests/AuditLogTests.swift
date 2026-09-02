import XCTest
@testable import Crumb

final class AuditLogTests: XCTestCase {
    private var testURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-audit-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        AuditLog.overrideURL = nil
        super.tearDown()
    }

    private func entry(domain: String = "a.com") -> AuditEntry {
        AuditEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mode: "test",
            browser: "Chrome",
            domain: domain,
            name: "cookie",
            path: "/",
            category: "unknown",
            verdict: "keep",
            reasoning: "test",
            result: "deleted",
            detail: nil
        )
    }

    func testAppendCreatesFileOnFirstWrite() throws {
        let url = testURL
        AuditLog.overrideURL = url
        defer { try? FileManager.default.removeItem(at: url) }

        // Regressie: FileHandle(forWritingTo:) faalt als audit.jsonl nog niet
        // bestaat — de allereerste verwijdering moest dan stilzwijgend verloren.
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try AuditLog.append([entry()])

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let loaded = AuditLog.allEntries(limit: 10)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.domain, "a.com")
        XCTAssertEqual(loaded.first?.result, "deleted")
    }

    func testAppendGrowsExistingFile() throws {
        let url = testURL
        AuditLog.overrideURL = url
        defer { try? FileManager.default.removeItem(at: url) }

        try AuditLog.append([entry(domain: "one.com")])
        try AuditLog.append([entry(domain: "two.com")])

        let loaded = AuditLog.allEntries(limit: 10)
        XCTAssertEqual(loaded.map(\.domain), ["two.com", "one.com"])
    }

    func testAppendWithEmptyEntriesDoesNotCreateFile() throws {
        let url = testURL
        AuditLog.overrideURL = url
        defer { try? FileManager.default.removeItem(at: url) }

        try AuditLog.append([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

import XCTest
@testable import Crumb

final class CookieBackupTests: XCTestCase {
    private var tempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-backup-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        CookieBackupStore.overrideDirectory = nil
        super.tearDown()
    }

    private func entry(store: String, browser: String = "Test") -> CookieBackupEntry {
        CookieBackupEntry(
            storePath: store,
            table: "cookies",
            browser: browser,
            values: [
                "host_key": .text("ads.example"),
                "name": .text("uid"),
                "path": .text("/"),
                "encrypted_value": .blob(Data([0x01, 0x02, 0xFE, 0xFF])),
                "score": .double(1.5),
                "priority": .int(7),
                "schema_version": .null
            ]
        )
    }

    func testBackupValueCodableRoundtrip() throws {
        let values: [BackupValue] = [.null, .int(-42), .double(3.25), .text("héllo"), .blob(Data([0, 255, 1]))]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(BackupValue.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func testWriteAndLoadRoundtrip() throws {
        CookieBackupStore.overrideDirectory = tempDirectory
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = try XCTUnwrap(CookieBackupStore.write(entries: [entry(store: "/tmp/x/Cookies")]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let file = try CookieBackupStore.load(from: url)
        XCTAssertEqual(file.entries.count, 1)
        XCTAssertEqual(file.entries[0].values["name"], .text("uid"))
        XCTAssertEqual(file.entries[0].values["encrypted_value"], .blob(Data([0x01, 0x02, 0xFE, 0xFF])))
        XCTAssertEqual(file.entries[0].values["schema_version"], .null)
    }

    func testBackupFileIsOwnerReadOnly() throws {
        CookieBackupStore.overrideDirectory = tempDirectory
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = try XCTUnwrap(CookieBackupStore.write(entries: [entry(store: "/tmp/x")]))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testWriteWithoutEntriesReturnsNil() throws {
        CookieBackupStore.overrideDirectory = tempDirectory
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        XCTAssertNil(try CookieBackupStore.write(entries: []))
        XCTAssertTrue(CookieBackupStore.listBackups().isEmpty)
    }

    func testListBackupsNewestFirst() throws {
        CookieBackupStore.overrideDirectory = tempDirectory
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        _ = try CookieBackupStore.write(entries: [entry(store: "/a")], createdAt: Date(timeIntervalSince1970: 100))
        _ = try CookieBackupStore.write(entries: [entry(store: "/b")], createdAt: Date(timeIntervalSince1970: 200))

        let backups = CookieBackupStore.listBackups()
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(backups[0].entryCount, 1)
        XCTAssertTrue(backups[0].createdAt > backups[1].createdAt)
    }

    func testDeleteBackupsOlderThan() throws {
        CookieBackupStore.overrideDirectory = tempDirectory
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let oldURL = try XCTUnwrap(CookieBackupStore.write(entries: [entry(store: "/a")], createdAt: Date().addingTimeInterval(-100 * 24 * 60 * 60)))
        let recentURL = try XCTUnwrap(CookieBackupStore.write(entries: [entry(store: "/b")], createdAt: Date()))

        // deleteBackups kijkt naar de modificatiedatum van het bestand —
        // simuleer een oud bestand expliciet.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-100 * 24 * 60 * 60)],
            ofItemAtPath: oldURL.path
        )

        let removed = try CookieBackupStore.deleteBackups(olderThan: 90 * 24 * 60 * 60)

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }
}

final class BackupRestoreRoundTripTests: XCTestCase {
    private var tempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-restore-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        CookieBackupStore.overrideDirectory = nil
        super.tearDown()
    }

    private func record(browser: String = "Test") -> CookieRecord {
        CookieRecord(
            domain: "ads.example", name: "uid", valueHash: "h", browser: browser, path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: Date(timeIntervalSince1970: 1), lastSeen: Date(timeIntervalSince1970: 2),
            category: .unknown, verdict: .keep, reasoning: "", protection: .none
        )
    }

    /// End-to-end: rij opslaan → captureRows → back-up → verwijderen →
    /// herstellen → rij is weer terug, exact dezelfde kolommen.
    func testCaptureBackupDeleteRestoreRoundtrip() async throws {
        let dir = tempDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CookieBackupStore.overrideDirectory = dir
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("Cookies")
        let db = try SQLiteDatabase(path: storeURL.path, readWrite: true, createIfNeeded: true)
        try db.execute("CREATE TABLE cookies (host_key TEXT, name TEXT, path TEXT, value TEXT, priority INTEGER, encrypted_value BLOB)")
        try db.execute(
            "INSERT INTO cookies (host_key, name, path, value, priority, encrypted_value) VALUES (?, ?, ?, ?, ?, ?)",
            parameters: [SQLiteValue.text(".ads.example"), .text("uid"), .text("/"), .text("secret-value"), .int(3), .blob(Data([9, 8, 7]))]
        )

        let stores = ["Test": [storeURL]]
        let captured = DeletionEngine.captureRows(for: [record()], stores: stores)
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].values["host_key"], .text(".ads.example"))
        XCTAssertEqual(captured[0].values["encrypted_value"], .blob(Data([9, 8, 7])))

        let backupURL = try XCTUnwrap(CookieBackupStore.write(entries: captured))
        try db.execute("DELETE FROM cookies WHERE host_key = '.ads.example' AND name = 'uid'")
        XCTAssertEqual(try db.query("SELECT * FROM cookies").count, 0)

        // "Test" is geen echte browser → isBrowserRunning is altijd false.
        let outcome = await CookieBackupStore.restore(from: backupURL)
        XCTAssertEqual(outcome.restored, 1)
        XCTAssertEqual(outcome.failed, 0)

        let rows = try db.query("SELECT * FROM cookies")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["host_key"], .text(".ads.example"))
        XCTAssertEqual(rows[0]["value"], .text("secret-value"))
        XCTAssertEqual(rows[0]["encrypted_value"], .blob(Data([9, 8, 7])))
        XCTAssertEqual(rows[0]["priority"], .int(3))
    }

    func testRestoreSkipsUnknownColumns() async throws {
        let dir = tempDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CookieBackupStore.overrideDirectory = dir
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("Cookies")
        let db = try SQLiteDatabase(path: storeURL.path, readWrite: true, createIfNeeded: true)
        try db.execute("CREATE TABLE cookies (host_key TEXT, name TEXT, path TEXT)")
        try db.execute(
            "INSERT INTO cookies (host_key, name, path) VALUES (?, ?, ?)",
            parameters: [SQLiteValue.text(".ads.example"), .text("uid"), .text("/")]
        )

        // Back-up bevat een kolom die in de tabel niet meer bestaat.
        let entry = CookieBackupEntry(
            storePath: storeURL.path,
            table: "cookies",
            browser: "Test",
            values: [
                "host_key": .text(".ads.example"),
                "name": .text("uid"),
                "path": .text("/"),
                "vanished_column": .text("x")
            ]
        )
        let backupURL = try XCTUnwrap(CookieBackupStore.write(entries: [entry]))
        try db.execute("DELETE FROM cookies")

        let outcome = await CookieBackupStore.restore(from: backupURL)
        XCTAssertEqual(outcome.restored, 1)
        XCTAssertEqual(try db.query("SELECT * FROM cookies").count, 1)
        XCTAssertEqual(try db.query("SELECT * FROM cookies")[0]["host_key"], .text(".ads.example"))
    }
}

final class ScanRunOriginTests: XCTestCase {
    func testOriginSurvivesCodable() throws {
        let run = ScanRun(startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2), sources: [], records: [], origin: "agent")
        let data = try JSONEncoder().encode(run)
        XCTAssertEqual(try JSONDecoder().decode(ScanRun.self, from: data).origin, "agent")
    }

    func testOldReportsWithoutOriginDecode() throws {
        let run = ScanRun(startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2), sources: [], records: [])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
        object.removeValue(forKey: "origin")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(ScanRun.self, from: stripped).origin)
    }
}

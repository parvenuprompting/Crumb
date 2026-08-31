import Foundation
import SQLite3

enum SQLiteValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    var intValue: Int64? {
        if case .int(let v) = self { return v }
        if case .double(let v) = self { return Int64(v) }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var textValue: String? {
        if case .text(let v) = self { return v }
        return nil
    }
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String, readWrite: Bool = false) throws {
        var db: OpaquePointer?
        let flags = readWrite ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "onbekende fout"
            sqlite3_close(db)
            throw CookieScanError.readFailed(message)
        }
        handle = db
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func tableColumns(table: String) throws -> [String] {
        var names: [String] = []
        let sql = "PRAGMA table_info(\(table))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CookieScanError.readFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) {
                names.append(String(cString: c))
            }
        }
        return names
    }

    func execute(_ sql: String, parameters: [String] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CookieScanError.readFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in parameters.enumerated() {
            guard sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                throw CookieScanError.readFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CookieScanError.readFailed(String(cString: sqlite3_errmsg(handle)))
        }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String) throws -> [[String: SQLiteValue]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CookieScanError.readFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [[String: SQLiteValue]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                guard let namePtr = sqlite3_column_name(stmt, i) else { continue }
                let name = String(cString: namePtr)
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row[name] = .int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[name] = .double(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    if let t = sqlite3_column_text(stmt, i) {
                        row[name] = .text(String(cString: t))
                    } else {
                        row[name] = .null
                    }
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(stmt, i) {
                        let length = Int(sqlite3_column_bytes(stmt, i))
                        row[name] = .blob(Data(bytes: bytes.assumingMemoryBound(to: UInt8.self), count: length))
                    } else {
                        row[name] = .blob(Data())
                    }
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }
}

enum StoreCopier {
    static func copyStore(at sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("crumb-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destination = tempDir.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            try fm.copyItem(at: sourceURL, to: destination)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain {
            if error.code == NSFileReadNoPermissionError {
                throw CookieScanError.fullDiskAccessRequired(path: sourceURL.path)
            }
            throw CookieScanError.readFailed(error.localizedDescription)
        }

        for suffix in ["-wal", "-journal", "-shm"] {
            let side = URL(fileURLWithPath: sourceURL.path + suffix)
            if fm.fileExists(atPath: side.path) {
                try? fm.copyItem(at: side, to: URL(fileURLWithPath: destination.path + suffix))
            }
        }
        return destination
    }
}

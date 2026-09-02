import Foundation

/// Eén celwaarde uit een cookie-database, JSON-vriendelijk geserialiseerd
/// (blobs als base64).
enum BackupValue: Codable, Sendable, Hashable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    private enum CodingKeys: String, CodingKey {
        case type, int, double, text, blob
    }

    init(_ value: SQLiteValue) {
        switch value {
        case .null: self = .null
        case .int(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .text(let v): self = .text(v)
        case .blob(let data): self = .blob(data)
        }
    }

    var sqliteValue: SQLiteValue {
        switch self {
        case .null: return .null
        case .int(let v): return .int(v)
        case .double(let v): return .double(v)
        case .text(let v): return .text(v)
        case .blob(let data): return .blob(data)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "null": self = .null
        case "int": self = .int(try container.decode(Int64.self, forKey: .int))
        case "double": self = .double(try container.decode(Double.self, forKey: .double))
        case "text": self = .text(try container.decode(String.self, forKey: .text))
        case "blob": self = .blob(try container.decode(Data.self, forKey: .blob))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Onbekend back-up-waardetype '\(other)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode("null", forKey: .type)
        case .int(let v):
            try container.encode("int", forKey: .type)
            try container.encode(v, forKey: .int)
        case .double(let v):
            try container.encode("double", forKey: .type)
            try container.encode(v, forKey: .double)
        case .text(let v):
            try container.encode("text", forKey: .type)
            try container.encode(v, forKey: .text)
        case .blob(let data):
            try container.encode("blob", forKey: .type)
            try container.encode(data, forKey: .blob)
        }
    }
}

/// Eén volledige database-rij die teruggezet kan worden.
struct CookieBackupEntry: Codable, Sendable, Hashable {
    let storePath: String
    let table: String
    let browser: String
    let values: [String: BackupValue]
}

struct CookieBackupFile: Codable, Sendable {
    let createdAt: Date
    let entries: [CookieBackupEntry]
}

struct BackupMetadata: Identifiable, Sendable {
    let url: URL
    let createdAt: Date
    let entryCount: Int
    var id: String { url.lastPathComponent }
}

struct RestoreOutcome: Sendable {
    let restored: Int
    let failed: Int
    let skippedStores: [String]

    var summary: String {
        var parts: [String] = ["\(restored) hersteld"]
        if failed > 0 { parts.append("\(failed) mislukt") }
        if !skippedStores.isEmpty {
            parts.append("overgeslagen: \(skippedStores.joined(separator: ", ")) (draait nog)")
        }
        return parts.joined(separator: " · ")
    }
}

enum CookieBackupStore {
    static var overrideDirectory: URL?

    static var directory: URL {
        overrideDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crumb/backups", isDirectory: true)
    }

    /// Schrijft een back-upbestand. nil bij een lege collectie (niets te back-uppen).
    @discardableResult
    static func write(entries: [CookieBackupEntry], createdAt: Date = Date()) throws -> URL? {
        guard !entries.isEmpty else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let url = directory.appendingPathComponent("backup-\(formatter.string(from: createdAt)).json")

        let file = CookieBackupFile(createdAt: createdAt, entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)

        // Back-ups bevatten cookie-waarden: alleen-lezen voor de eigenaar.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    static func load(from url: URL) throws -> CookieBackupFile {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CookieBackupFile.self, from: data)
    }

    static func listBackups(limit: Int = 10) -> [BackupMetadata] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("backup-") })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
            .prefix(limit) else {
            return []
        }
        return files.compactMap { url in
            guard let file = try? load(from: url) else { return nil }
            return BackupMetadata(url: url, createdAt: file.createdAt, entryCount: file.entries.count)
        }
    }

    static func deleteBackups(olderThan interval: TimeInterval, now: Date = Date()) throws -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }
        var removed = 0
        for file in files where file.pathExtension == "json" {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > interval else { continue }
            try? fm.removeItem(at: file)
            removed += 1
        }
        return removed
    }

    /// Zet geback-upte rijen terug in hun oorspronkelijke cookie-store.
    /// Browsers die draaien worden overgeslagen (zelfde beleid als verwijderen).
    static func restore(from url: URL) async -> RestoreOutcome {
        guard let file = try? load(from: url) else {
            return RestoreOutcome(restored: 0, failed: 0, skippedStores: ["onleesbaar back-upbestand"])
        }

        var restored = 0
        var failed = 0
        var skipped: [String] = []
        let byStore = Dictionary(grouping: file.entries, by: \.storePath)

        for (storePath, entries) in byStore {
            let browser = entries.first?.browser ?? ""
            if DeletionEngine.isBrowserRunning(browser) {
                skipped.append(browser.isEmpty ? storePath : browser)
                continue
            }
            guard let db = try? SQLiteDatabase(path: storePath, readWrite: true) else {
                failed += entries.count
                continue
            }
            let available = Set((try? db.tableColumns(table: entries[0].table)) ?? [])

            for entry in entries {
                // Alleen kolommen die nu nog bestaan; de rest vangt de tabeldefault op.
                let columns = entry.values.keys.sorted().filter { available.contains($0) }
                guard !columns.isEmpty else {
                    failed += 1
                    continue
                }
                let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
                let sql = "INSERT OR REPLACE INTO \(entry.table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))"
                let parameters: [SQLiteValue] = columns.map { entry.values[$0]?.sqliteValue ?? .null }
                do {
                    _ = try db.execute(sql, parameters: parameters)
                    restored += 1
                } catch {
                    failed += 1
                }
            }
        }
        return RestoreOutcome(restored: restored, failed: failed, skippedStores: skipped)
    }
}

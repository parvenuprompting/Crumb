import Foundation

struct AuditEntry: Codable, Sendable {
    let timestamp: Date
    let mode: String
    let browser: String
    let domain: String
    let name: String
    let path: String
    let category: String
    let verdict: String
    let reasoning: String
    let result: String
    let detail: String?
}

enum AuditLog {
    /// Test-seam: laat tests naar een tijdelijk bestand schrijven.
    static var overrideURL: URL?

    static var fileURL: URL {
        overrideURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crumb/audit.jsonl")
    }

    static func append(_ entries: [AuditEntry]) throws {
        guard !entries.isEmpty else { return }
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // FileHandle(forWritingTo:) faalt als het bestand nog niet bestaat —
        // maak het expliciet aan zodat de allereerste verwijdering gelogd wordt.
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var lines = ""
        for entry in entries {
            lines += String(data: try encoder.encode(entry), encoding: .utf8)! + "\n"
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines.utf8))
    }

    static func allEntries(limit: Int = 200) -> [AuditEntry] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return contents
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { line -> AuditEntry? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(AuditEntry.self, from: data)
            }
            .reversed()
    }

    // MARK: Export

    static func csv(entries: [AuditEntry]) -> String {
        let header = "timestamp,mode,browser,domain,name,path,category,verdict,result,detail"
        let formatter = ISO8601DateFormatter()
        var rows: [String] = [header]
        for entry in entries {
            let fields: [String] = [
                formatter.string(from: entry.timestamp),
                entry.mode,
                entry.browser,
                entry.domain,
                entry.name,
                entry.path,
                entry.category,
                entry.verdict,
                entry.result,
                entry.detail ?? ""
            ]
            rows.append(fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func exportCSV(entries: [AuditEntry], to url: URL) throws {
        try csv(entries: entries).write(to: url, atomically: true, encoding: .utf8)
    }

    static func exportJSON(entries: [AuditEntry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}

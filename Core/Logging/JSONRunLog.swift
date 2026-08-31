import Foundation

enum JSONRunLog {
    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crumb/logs", isDirectory: true)
    }

    static func write(run: ScanRun) throws -> URL {
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let fileURL = logsDirectory.appendingPathComponent("run-\(formatter.string(from: run.startedAt)).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(run)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func lastRun() -> ScanRun? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("run-") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
            let newest = files.last else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: newest),
              let run = try? decoder.decode(ScanRun.self, from: data) else {
            return nil
        }
        return run
    }

    static func allRuns(limit: Int = 30) -> [ScanRun] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("run-") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .suffix(limit) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ScanRun.self, from: data)
        }
    }

    static func deleteLogs(olderThan interval: TimeInterval, now: Date = Date()) throws -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return 0
        }
        var removed = 0
        for file in files where file.pathExtension == "json" {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > interval else { continue }
            try? fm.removeItem(at: file)
            removed += 1
        }
        return removed
    }
}

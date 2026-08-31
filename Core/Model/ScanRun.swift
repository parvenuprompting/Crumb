import Foundation

struct ScanSourceStatus: Codable, Hashable, Sendable {
    let browser: String
    let scanned: Bool
    let cookieCount: Int
    let error: String?
    let requiresFullDiskAccess: Bool
}

struct ScanRun: Codable, Hashable, Sendable {
    let startedAt: Date
    let finishedAt: Date
    let sources: [ScanSourceStatus]
    let records: [CookieRecord]

    var categoryCounts: [CookieCategory: Int] {
        Dictionary(grouping: records, by: \.category).mapValues(\.count)
    }

    var verdictCounts: [CookieVerdict: Int] {
        Dictionary(grouping: records, by: \.verdict).mapValues(\.count)
    }

    var browserCounts: [String: Int] {
        Dictionary(grouping: records, by: \.browser).mapValues(\.count)
    }

    var lockedCount: Int {
        records.filter(\.protection.isLocked).count
    }
}

struct SnapshotEntry: Codable, Sendable {
    var firstSeen: Date
    var lastSeen: Date
}

struct SnapshotStore: Codable, Sendable {
    var entries: [String: SnapshotEntry] = [:]

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crumb/snapshot.json")
    }

    static func load() -> SnapshotStore {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(SnapshotStore.self, from: data) else {
            return SnapshotStore()
        }
        return store
    }

    func save() throws {
        let dir = Self.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.fileURL, options: .atomic)
    }

    func entry(for record: CookieRecord) -> SnapshotEntry? {
        entries[record.id]
    }

    mutating func recordLastSeen(_ id: String, at date: Date, firstSeenFallback: Date) {
        if var entry = entries[id] {
            entry.lastSeen = date
            entries[id] = entry
        } else {
            entries[id] = SnapshotEntry(firstSeen: firstSeenFallback, lastSeen: date)
        }
    }
}

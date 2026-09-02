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
    var aiUsed: Bool? = nil
    var aiClassifiedCount: Int? = nil
    var aiSkippedReason: String? = nil

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
    /// Laatst geziene waarde-hash per browser — hashes zijn browserspecifiek
    /// (Chromium versleutelt per browser), dus nooit één gedeelde hash vergelijken.
    var lastValueHashes: [String: String]? = nil
    /// Aantal waardeveranderingen per browser sinds de eerste waarneming.
    var churnCounts: [String: Int]? = nil
}

struct SnapshotStore: Codable, Sendable {
    var entries: [String: SnapshotEntry] = [:]

    /// Test-seam: laat tests naar een tijdelijk bestand schrijven.
    static var overrideFileURL: URL?

    static var fileURL: URL {
        overrideFileURL ?? FileManager.default.homeDirectoryForCurrentUser
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

    mutating func recordLastSeen(_ id: String, at date: Date, firstSeenFallback: Date) {
        recordObservation(id, browser: "", valueHash: nil, at: date, firstSeenFallback: firstSeenFallback)
    }

    /// Registreert een waarneming: werkt lastSeen bij, onthoudt de
    /// waarde-hash per browser en telt churn wanneer dezelfde browser een
    /// ándere hash ziet dan de vorige run.
    mutating func recordObservation(
        _ id: String,
        browser: String,
        valueHash: String?,
        at date: Date,
        firstSeenFallback: Date
    ) {
        var entry = entries[id] ?? SnapshotEntry(firstSeen: firstSeenFallback, lastSeen: date)
        entry.lastSeen = date
        if let valueHash {
            var hashes = entry.lastValueHashes ?? [:]
            if let previous = hashes[browser], previous != valueHash {
                var counts = entry.churnCounts ?? [:]
                counts[browser, default: 0] += 1
                entry.churnCounts = counts
            }
            hashes[browser] = valueHash
            entry.lastValueHashes = hashes
        }
        entries[id] = entry
    }
}

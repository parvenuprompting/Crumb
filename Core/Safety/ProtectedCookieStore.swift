import Foundation

/// Handmatig beschermd door de gebruiker ("alleen deze cookie beschermen").
/// Key: domain|name|path — exact één cookie, geen heel domein.
struct ProtectedCookieStore: Codable, Sendable, Hashable {
    var keys: [String] = []

    static var overrideFileURL: URL?

    static var fileURL: URL {
        overrideFileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crumb", isDirectory: true)
            .appendingPathComponent("protected-cookies.json")
    }

    static func load() -> ProtectedCookieStore {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(ProtectedCookieStore.self, from: data) else {
            return ProtectedCookieStore()
        }
        return store
    }

    func save() throws {
        let dir = Self.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
    }

    static func key(domain: String, name: String, path: String) -> String {
        "\(domain)|\(name)|\(path)"
    }

    func contains(domain: String, name: String, path: String) -> Bool {
        keys.contains(Self.key(domain: domain, name: name, path: path))
    }

    mutating func add(domain: String, name: String, path: String) {
        let key = Self.key(domain: domain, name: name, path: path)
        if !keys.contains(key) { keys.append(key) }
    }

    mutating func remove(domain: String, name: String, path: String) {
        let key = Self.key(domain: domain, name: name, path: path)
        keys.removeAll { $0 == key }
    }
}

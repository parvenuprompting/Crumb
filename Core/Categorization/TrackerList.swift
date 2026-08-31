import Foundation

struct TrackerList: Sendable {
    let suffixes: Set<String>

    init(suffixes: Set<String>) {
        self.suffixes = suffixes
    }

    init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "tracker-domains", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var entries: Set<String> = []
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            entries.insert(trimmed.lowercased())
        }
        suffixes = entries
    }

    func isTracker(domain: String) -> Bool {
        let normalized = domain.lowercased()
        if suffixes.contains(normalized) { return true }
        return suffixes.contains { normalized.hasSuffix(".\($0)") }
    }
}

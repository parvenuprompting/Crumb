import Foundation

struct TrackerList: Sendable {
    let suffixes: Set<String>

    init(suffixes: Set<String>) {
        self.suffixes = suffixes
    }

    init?(bundle: Bundle = .main) {
        var resourceURL = bundle.url(forResource: "tracker-domains", withExtension: "txt")
        if resourceURL == nil, let executablePath = CommandLine.arguments.first {
            let candidate = URL(fileURLWithPath: executablePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../Resources/tracker-domains.txt")
            if FileManager.default.fileExists(atPath: candidate.standardizedFileURL.path) {
                resourceURL = candidate
            }
        }
        guard let url = resourceURL,
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

    /// Matcht het domein en elk van zijn suffixen tegen de lijst via O(labels)
    /// set-lookups — schaalbaar naar lijsten met tienduizenden domeinen.
    func isTracker(domain: String) -> Bool {
        var label = domain.lowercased()
        guard !label.isEmpty else { return false }
        if suffixes.contains(label) { return true }
        while let firstDot = label.firstIndex(of: ".") {
            label = String(label[label.index(after: firstDot)...])
            if suffixes.contains(label) { return true }
        }
        return false
    }
}

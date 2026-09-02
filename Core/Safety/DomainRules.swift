import Foundation

/// Fijnmazige regels naast de whitelist, per domein (met optionele
/// cookienaam- en browserfilter).
struct DomainRule: Codable, Sendable, Identifiable, Hashable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case alwaysKeep = "Altijd bewaren"
        case alwaysTracking = "Altijd als tracking"
        case cleanupOlderThan = "Opschonen ouder dan (dagen)"
        case protectCookieName = "Cookienaam beschermen"
        case deleteCookieName = "Cookienaam opschonen"

        var id: String { rawValue }
    }

    var domain: String
    var action: Action
    var cookieName: String? = nil
    var browser: String? = nil
    var olderThanDays: Int? = nil

    var id: String { "\(domain)|\(action.rawValue)|\(cookieName ?? "")|\(browser ?? "")" }

    var summary: String {
        var parts: [String] = [domain]
        switch action {
        case .alwaysKeep: parts.append("altijd bewaren")
        case .alwaysTracking: parts.append("altijd als tracking markeren")
        case .cleanupOlderThan: parts.append("opschonen ouder dan \(olderThanDays ?? 0) dagen")
        case .protectCookieName: parts.append("cookienaam '\(cookieName ?? "")' beschermen")
        case .deleteCookieName: parts.append("cookienaam '\(cookieName ?? "")' opschonen")
        }
        if let browser, !browser.isEmpty { parts.append("alleen \(browser)") }
        return parts.joined(separator: " — ")
    }
}

struct DomainRulesStore: Codable, Sendable {
    var rules: [DomainRule] = []

    static var overrideFileURL: URL?

    static var fileURL: URL {
        overrideFileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crumb", isDirectory: true)
            .appendingPathComponent("domain-rules.json")
    }

    static func load() -> DomainRulesStore {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(DomainRulesStore.self, from: data) else {
            return DomainRulesStore()
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
}

/// Past de domeinregels toe op een geclassificeerd record. De safelist wint
/// altijd: regels kunnen bescherming nooit omzeilen.
enum DomainRulesEngine {
    struct Outcome: Sendable {
        var category: CookieCategory?
        var verdict: CookieVerdict?
        var reasoning: String?
        var protection: CookieProtection?
    }

    static func matchingRules(for record: CookieRecord, rules: [DomainRule]) -> [DomainRule] {
        rules.filter { rule in
            let domainMatches = record.domain == rule.domain
                || record.domain.hasSuffix(".\(rule.domain)")
            let nameMatches = rule.cookieName == nil
                || rule.cookieName!.isEmpty
                || rule.cookieName == record.name
            let browserMatches = rule.browser == nil
                || rule.browser!.isEmpty
                || rule.browser == record.browser
            return domainMatches && nameMatches && browserMatches
        }
    }

    static func apply(_ rules: [DomainRule], to record: CookieRecord, now: Date = Date()) -> Outcome {
        let matching = matchingRules(for: record, rules: rules)
        guard !matching.isEmpty else { return Outcome() }

        var outcome = Outcome()
        for rule in matching {
            switch rule.action {
            case .alwaysKeep:
                outcome.protection = .locked("Regel: '\(rule.domain)' altijd bewaren.")
            case .protectCookieName:
                if let name = rule.cookieName, !name.isEmpty, name == record.name {
                    outcome.protection = .locked("Regel: cookienaam '\(name)' beschermen.")
                }
            case .alwaysTracking:
                guard record.protection == .none else { break }
                outcome.category = .marketingTracking
                if outcome.verdict == nil {
                    outcome.verdict = .reviewSuggested
                    outcome.reasoning = "Regel: domein gemarkeerd als tracking."
                }
            case .cleanupOlderThan:
                guard record.protection == .none,
                      record.verdict != .keep,
                      let days = rule.olderThanDays, days > 0,
                      now.timeIntervalSince(record.firstSeen) >= TimeInterval(days) * 86_400 else { break }
                outcome.verdict = .safeToClean
                outcome.reasoning = "Regel: ouder dan \(days) dagen op '\(rule.domain)' → opschonen."
            case .deleteCookieName:
                guard record.protection == .none,
                      let name = rule.cookieName, !name.isEmpty, name == record.name else { break }
                outcome.verdict = .safeToClean
                outcome.reasoning = "Regel: cookienaam '\(name)' altijd opschonen."
            }
        }

        // Bescherming wint altijd, ook als een later regeltype iets anders wil.
        if case .locked = outcome.protection {
            outcome.verdict = .keep
        }
        return outcome
    }
}

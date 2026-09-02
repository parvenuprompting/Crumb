import Foundation

/// Eén concrete aanbeveling op het dashboard, gesorteerd op impact.
struct CookieRecommendation: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable {
        case safeToClean
        case staleCookies
        case reappearingTrackers
        case topDomains
    }

    let kind: Kind
    let title: String
    let detail: String
    let impact: Int
    let recordCount: Int

    var id: String { kind.rawValue }

    var systemImage: String {
        switch kind {
        case .safeToClean: return "checkmark.seal"
        case .staleCookies: return "clock.badge.exclamationmark"
        case .reappearingTrackers: return "arrow.clockwise"
        case .topDomains: return "globe"
        }
    }
}

/// Zet de scanresultaten om in een prioriteitenlijst met acties.
enum RecommendationEngine {
    static let staleAgeThreshold: TimeInterval = 90 * 86_400
    static let reappearingMinimumRuns = 3
    static let historyWindow = 5

    static func recommendations(
        for run: ScanRun,
        history: [ScanRun] = [],
        now: Date = Date()
    ) -> [CookieRecommendation] {
        var result: [CookieRecommendation] = []

        // 1. Veilig op te ruimen — de hoofdactie.
        let safe = run.records.filter { $0.verdict == .safeToClean && !$0.protection.isLocked }
        if !safe.isEmpty {
            result.append(CookieRecommendation(
                kind: .safeToClean,
                title: "\(safe.count) cookies kunnen veilig worden verwijderd",
                detail: "Bevestigd door regellaag en AI, geen bescherming actief.",
                impact: 1000 + safe.count,
                recordCount: safe.count
            ))
        }

        // 2. Oud en niet-essentieel — hardnekkig achtergebleven.
        let stale = run.records.filter { record in
            guard record.protection == .none else { return false }
            guard record.verdict != .keep else { return false }
            return now.timeIntervalSince(record.firstSeen) > staleAgeThreshold
        }
        if !stale.isEmpty {
            result.append(CookieRecommendation(
                kind: .staleCookies,
                title: "\(stale.count) cookies zijn ouder dan 90 dagen",
                detail: "Niet-essentieel en lang aanwezig — opschoonkandidaten.",
                impact: 500 + stale.count,
                recordCount: stale.count
            ))
        }

        // 3. Trackers die telkens terugkomen (uit eerdere runs).
        let historyRuns = history.filter { $0.finishedAt < run.startedAt }.suffix(historyWindow)
        if historyRuns.count >= reappearingMinimumRuns {
            var presence: [String: Int] = [:]
            for past in historyRuns {
                for domain in Set(past.records.filter { $0.category == .marketingTracking }.map(\.domain)) {
                    presence[domain, default: 0] += 1
                }
            }
            let persistentDomains = Set(presence.filter { $0.value >= reappearingMinimumRuns }.keys)
            if !persistentDomains.isEmpty {
                let current = run.records.filter { $0.category == .marketingTracking && persistentDomains.contains($0.domain) }
                let top = Array(persistentDomains.sorted().prefix(3)).joined(separator: ", ")
                result.append(CookieRecommendation(
                    kind: .reappearingTrackers,
                    title: "\(current.count) tracking-cookies worden vaak opnieuw aangemaakt",
                    detail: "Terugkerend in minstens \(reappearingMinimumRuns) van de laatste \(historyWindow) runs: \(top).",
                    impact: 400 + current.count,
                    recordCount: current.count
                ))
            }
        }

        // 4. Een handjevol domeinen veroorzaakt het grootste deel van de tracking.
        let tracking = run.records.filter { $0.category == .marketingTracking }
        if tracking.count >= 4 {
            var counts: [String: Int] = [:]
            for record in tracking { counts[record.domain, default: 0] += 1 }
            let sorted = counts.sorted { $0.value > $1.value }
            var covered = 0
            var taken = 0
            for (_, count) in sorted {
                covered += count
                taken += 1
                if Double(covered) >= Double(tracking.count) * 0.7 { break }
            }
            result.append(CookieRecommendation(
                kind: .topDomains,
                title: "\(taken) domeinen veroorzaken \(Int((Double(covered) / Double(tracking.count) * 100).rounded()))% van je tracking-cookies",
                detail: "Een whitelist of gerichte opschoning daar werkt het hardst.",
                impact: 300 + covered,
                recordCount: covered
            ))
        }

        return result.sorted { $0.impact > $1.impact }
    }
}

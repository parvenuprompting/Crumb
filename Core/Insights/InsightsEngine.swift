import Foundation

/// Diff tussen twee scans: nieuw verschenen en verdwenen cookies.
/// Identiteit is browser-agnostisch (domain|name|path), net als de snapshot.
struct CookieDiff: Sendable, Equatable {
    let newCookies: [CookieRecord]
    let disappearedCookies: [CookieRecord]
}

/// Cookies die in meerdere browsers voorkomen (duplicaten).
struct BrowserSharing: Sendable, Identifiable, Hashable {
    let domain: String
    let name: String
    let browsers: [String]
    let isTracking: Bool

    var key: String { "\(domain)|\(name)" }
    var id: String { key }
    var browserCount: Int { browsers.count }
}

/// Privacy-score 0–100: hoger is beter. Trackerdruk weegt het zwaarst,
/// onbekende en nog-niet-opgeruimde cookies tellen lichter mee.
struct PrivacyScore: Sendable, Equatable {
    let score: Int
    let label: String
    let explanation: String
    /// Verandering in tracking-cookies t.o.v. de vorige run (positief = meer).
    let trackingDelta: Int?
    /// Percentage verandering in trackerdruk t.o.v. de vorige run.
    let trackingDeltaPercent: Double?
}

enum InsightsEngine {
    // MARK: Diff

    static func diff(current: ScanRun, prior: ScanRun) -> CookieDiff {
        let priorKeys = Set(prior.records.map { "\($0.domain)|\($0.name)|\($0.path)" })
        let currentKeys = Set(current.records.map { "\($0.domain)|\($0.name)|\($0.path)" })

        let added = current.records.filter { !priorKeys.contains("\($0.domain)|\($0.name)|\($0.path)") }
        let gone = prior.records.filter { !currentKeys.contains("\($0.domain)|\($0.name)|\($0.path)") }
        return CookieDiff(newCookies: added, disappearedCookies: gone)
    }

    // MARK: Browservergelijking

    static func browserSharing(in run: ScanRun) -> [BrowserSharing] {
        var groups: [String: (browsers: Set<String>, tracking: Bool)] = [:]
        for record in run.records {
            let key = "\(record.domain)|\(record.name)"
            var entry = groups[key] ?? (browsers: [], tracking: false)
            entry.browsers.insert(record.browser)
            if record.category == .marketingTracking { entry.tracking = true }
            groups[key] = entry
        }
        return groups
            .map { key, value in
                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                return BrowserSharing(
                    domain: parts.count > 0 ? parts[0] : "",
                    name: parts.count > 1 ? parts[1] : "",
                    browsers: value.browsers.sorted(),
                    isTracking: value.tracking
                )
            }
            .sorted { a, b in
                if a.browserCount != b.browserCount { return a.browserCount > b.browserCount }
                return a.domain < b.domain
            }
    }

    /// Cookies die in álle actieve browsers tegelijk aanwezig zijn — de
    /// hardnekkigste cross-browser tracking-duplicaten.
    static func trackingInAllBrowsers(in run: ScanRun) -> [BrowserSharing] {
        let browserCount = Set(run.records.map(\.browser)).count
        guard browserCount > 1 else { return [] }
        return browserSharing(in: run).filter { $0.isTracking && $0.browserCount == browserCount }
    }

    // MARK: Churn & persistentie

    static func topChurn(in run: ScanRun, limit: Int = 5) -> [CookieRecord] {
        run.records
            .filter { ($0.valueChurn ?? 0) > 0 }
            .sorted { ($0.valueChurn ?? 0) > ($1.valueChurn ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    /// Domeinen met tracking-cookies die in de meeste recente runs voorkomen.
    static func mostPersistentTrackingDomains(runs: [ScanRun], limit: Int = 10) -> [(domain: String, runs: Int)] {
        var presence: [String: Int] = [:]
        for run in runs {
            for domain in Set(run.records.filter { $0.category == .marketingTracking }.map(\.domain)) {
                presence[domain, default: 0] += 1
            }
        }
        return presence
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    // MARK: Privacy-score

    static func privacyScore(for run: ScanRun, priorRuns: [ScanRun] = []) -> PrivacyScore {
        let total = run.records.count
        guard total > 0 else {
            return PrivacyScore(
                score: 100,
                label: "Geen cookies",
                explanation: "Er zijn nog geen cookies waargenomen.",
                trackingDelta: nil,
                trackingDeltaPercent: nil
            )
        }

        let tracking = run.records.filter { $0.category == .marketingTracking }.count
        let unknown = run.records.filter { $0.category == .unknown || $0.category == .thirdPartyUnknown }.count
        let pendingSafe = run.verdictCounts[.safeToClean, default: 0]

        var score = 100.0
            - (Double(tracking) / Double(total)) * 55
            - (Double(unknown) / Double(total)) * 25
            - (Double(pendingSafe) / Double(total)) * 20
        score = max(0, min(100, score.rounded()))

        let prior = priorRuns.last { $0.finishedAt < run.startedAt }
        var trackingDelta: Int?
        var trackingDeltaPercent: Double?
        if let prior {
            let priorTracking = prior.records.filter { $0.category == .marketingTracking }.count
            trackingDelta = tracking - priorTracking
            if priorTracking > 0 {
                trackingDeltaPercent = (Double(tracking - priorTracking) / Double(priorTracking)) * 100
            }
        }

        let label: String
        switch score {
        case 80...: label = "Goed beschermd"
        case 60..<80: label = "Acceptabel"
        default: label = "Aandacht nodig"
        }

        var explanation = "\(tracking) van \(total) cookies zijn tracking, \(unknown) onbekend, \(pendingSafe) wachten op opruiming."
        if let delta = trackingDelta, delta != 0 {
            let direction = delta < 0 ? "gedaald" : "gestegen"
            if let percent = trackingDeltaPercent {
                explanation += " Trackerdruk is \(Int(abs(percent.rounded())))% \(direction) t.o.v. de vorige run."
            } else {
                explanation += " Trackerdruk is \(abs(delta)) cookies \(direction) t.o.v. de vorige run."
            }
        }
        return PrivacyScore(
            score: Int(score),
            label: label,
            explanation: explanation,
            trackingDelta: trackingDelta,
            trackingDeltaPercent: trackingDeltaPercent
        )
    }
}

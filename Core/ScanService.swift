import Foundation

/// Fases van een scan, in volgorde — voor de voortgangsweergave.
enum ScanPhase: String, CaseIterable, Sendable {
    case idle
    case detectingBrowsers
    case readingStores
    case applyingRules
    case aiClassification
    case checkingSafelist
    case savingReport

    var displayName: String {
        switch self {
        case .idle: return "Niet actief"
        case .detectingBrowsers: return "Browsers detecteren"
        case .readingStores: return "Cookie-stores lezen"
        case .applyingRules: return "Regels toepassen"
        case .aiClassification: return "AI-classificatie uitvoeren"
        case .checkingSafelist: return "Safelist controleren"
        case .savingReport: return "Rapport opslaan"
        }
    }

    var stepNumber: Int? {
        Self.allCases.firstIndex(of: self).map { $0 + 1 }
    }
}

@MainActor
final class ScanService: ObservableObject {
    static let shared = ScanService()

    @Published private(set) var isScanning = false
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var liveSourceStatuses: [ScanSourceStatus] = []
    @Published private(set) var lastRun: ScanRun?
    @Published private(set) var lastError: String?

    private let fileManager = FileManager.default

    var sourceAvailability: [SourceAvailability] {
        Self.buildSources().map { source in
            let safariAccess = (source as? SafariSource)?.isAccessible ?? true
            return SourceAvailability(
                browser: source.browserName,
                isInstalled: source.isInstalled,
                isAccessible: safariAccess,
                requiresFullDiskAccess: source is SafariSource && !safariAccess
            )
        }
    }

    struct SourceAvailability: Identifiable, Hashable {
        let browser: String
        let isInstalled: Bool
        let isAccessible: Bool
        let requiresFullDiskAccess: Bool

        var id: String { browser }
    }

    static func buildSources() -> [any CookieSource] {
        [
            ChromiumSource(config: .chrome),
            ChromiumSource(config: .brave),
            SafariSource(),
            FirefoxSource()
        ]
    }

    func checkAvailability() {
        objectWillChange.send()
    }

    /// Laadt de laatste run van disk (bijv. van de achtergrond-agent) zodat de
    /// UI direct een actuele stand toont, ook vóór de eerste scan in deze sessie.
    func loadLastRunFromDisk() {
        guard lastRun == nil else { return }
        lastRun = JSONRunLog.lastRun()
    }

    func runScan() async {
        guard !isScanning else { return }
        isScanning = true
        lastError = nil
        liveSourceStatuses = []
        phase = .detectingBrowsers
        defer { isScanning = false; phase = .idle }

        let settings = SettingsStore.shared
        let whitelist = Set(WhitelistStore.load().domains.map(WhitelistStore.normalizedDomain))
        let protectedCookies = Set(ProtectedCookieStore.load().keys)
        let ollamaEnabled = settings.ollamaEnabled
        let ollamaModel = settings.ollamaModel

        guard let trackerList = TrackerList() else {
            lastError = "Tracker-domeinenlijst ontbreekt in de app-bundle."
            return
        }

        let startedAt = Date()
        phase = .readingStores
        let sources = Self.buildSources()
        let (statuses, cookies) = await Self.scanSources(sources) { status in
            Task { @MainActor in
                ScanService.shared.liveSourceStatuses.append(status)
            }
        }
        var rawCookies = cookies

        var aiUsed = false
        var aiSkippedReason: String?
        var aiClassified = 0

        if ollamaEnabled {
            phase = .aiClassification
            let result = await Self.classifyWithAI(
                rawCookies: rawCookies,
                trackerList: trackerList,
                model: ollamaModel,
                now: startedAt
            )
            rawCookies = result.cookies
            aiUsed = result.used
            aiClassified = result.classifiedCount
            aiSkippedReason = result.skippedReason
        }

        phase = .applyingRules
        let records = await Self.buildRecords(
            rawCookies: rawCookies,
            whitelist: whitelist,
            trackerList: trackerList,
            now: startedAt,
            protectedCookies: protectedCookies
        )
        phase = .checkingSafelist

        let finishedAt = Date()
        let run = ScanRun(
            startedAt: startedAt,
            finishedAt: finishedAt,
            sources: statuses,
            records: records,
            aiUsed: aiUsed,
            aiClassifiedCount: aiClassified,
            aiSkippedReason: aiSkippedReason,
            origin: "app"
        )
        lastRun = run

        phase = .savingReport
        do {
            try await Self.persist(run: run)
        } catch {
            lastError = "Kon run niet wegschrijven: \(error.localizedDescription)"
        }

        // Onderhoud: rapporten en back-ups niet onbeperkt laten groeien.
        try? JSONRunLog.deleteLogs(olderThan: Self.retentionInterval)
        try? CookieBackupStore.deleteBackups(olderThan: Self.retentionInterval)
    }

    nonisolated static let retentionInterval: TimeInterval = 90 * 24 * 60 * 60

    nonisolated static func scanSources(
        _ sources: [any CookieSource],
        onSourceDone: (@Sendable (ScanSourceStatus) -> Void)? = nil
    ) async -> (statuses: [ScanSourceStatus], cookies: [RawCookie]) {
        var statuses: [ScanSourceStatus] = []
        var allCookies: [RawCookie] = []
        allCookies.reserveCapacity(2000)

        for source in sources {
            guard source.isInstalled else {
                let status = ScanSourceStatus(browser: source.browserName, scanned: false, cookieCount: 0, error: nil, requiresFullDiskAccess: false)
                statuses.append(status)
                onSourceDone?(status)
                continue
            }
            do {
                let cookies = try source.scan().map { raw -> RawCookie in
                    var tagged = raw
                    tagged.browser = source.browserName
                    return tagged
                }
                allCookies.append(contentsOf: cookies)
                let status = ScanSourceStatus(browser: source.browserName, scanned: true, cookieCount: cookies.count, error: nil, requiresFullDiskAccess: false)
                statuses.append(status)
                onSourceDone?(status)
            } catch CookieScanError.fullDiskAccessRequired {
                let status = ScanSourceStatus(browser: source.browserName, scanned: false, cookieCount: 0, error: "Volledige Schijftoegang vereist", requiresFullDiskAccess: true)
                statuses.append(status)
                onSourceDone?(status)
            } catch {
                let status = ScanSourceStatus(browser: source.browserName, scanned: false, cookieCount: 0, error: error.localizedDescription, requiresFullDiskAccess: false)
                statuses.append(status)
                onSourceDone?(status)
            }
        }
        return (statuses, allCookies)
    }

    nonisolated static func classifyWithAI(
        rawCookies: [RawCookie],
        trackerList: TrackerList,
        model: String,
        now: Date
    ) async -> (cookies: [RawCookie], used: Bool, classifiedCount: Int, skippedReason: String?) {
        let client = OllamaClient()
        do {
            try await client.verify(model: model)
            let engine = RuleEngine(trackerList: trackerList, now: now)
            let candidates = rawCookies
                .filter { engine.isAICandidate($0) }
                .sorted { a, b in
                    let pa = aiPriority(engine.provisionalCategory(for: a))
                    let pb = aiPriority(engine.provisionalCategory(for: b))
                    if pa != pb { return pa < pb }
                    let da = a.domain.lowercased()
                    let db = b.domain.lowercased()
                    if da != db { return da < db }
                    return a.name.lowercased() < b.name.lowercased()
                }
            let inputs = candidates.map { cookie in
                CookiePromptInput(
                    domain: cookie.domain,
                    name: cookie.name,
                    isSecure: cookie.isSecure,
                    isHttpOnly: cookie.isHttpOnly,
                    isSessionOnly: cookie.isSessionOnly,
                    hasExpiry: cookie.expiry != nil,
                    expiresInSeconds: cookie.expiry.map { Int($0.timeIntervalSince(now)) },
                    browser: cookie.browser
                )
            }
            let judgements = await client.classifyAll(model: model, cookies: inputs)

            var byKey: [String: LLMCookieJudgement] = [:]
            for judgement in judgements {
                byKey["\(judgement.domain)|\(judgement.name)"] = judgement
            }

            var classified = 0
            var updated = rawCookies
            for index in updated.indices {
                guard engine.isAICandidate(updated[index]) else { continue }
                let key = "\(updated[index].domain.lowercased())|\(updated[index].name)"
                guard let judgement = byKey[key] else { continue }
                updated[index].aiCategory = judgement.category
                updated[index].aiVerdict = judgement.verdict
                updated[index].aiReasoning = judgement.reasoning
                classified += 1
            }
            let used = !judgements.isEmpty
            let reason: String? = used ? nil : "AI geactiveerd, maar er kwamen geen bruikbare antwoorden terug."
            return (updated, used, classified, reason)
        } catch {
            return (rawCookies, false, 0, "AI-classificatie overgeslagen: \(error.localizedDescription)")
        }
    }

    /// Binnen de batchcap krijgt 'onbekend' voorrang (meeste winst), daarna
    /// regel-laag-kandidaten die bevestiging nodig hebben.
    nonisolated private static func aiPriority(_ category: CookieCategory) -> Int {
        switch category {
        case .unknown: return 0
        case .marketingTracking: return 1
        case .analytics: return 2
        default: return 3
        }
    }

    nonisolated static func buildRecords(
        rawCookies: [RawCookie],
        whitelist: Set<String>,
        trackerList: TrackerList,
        now: Date,
        protectedCookies: Set<String> = []
    ) async -> [CookieRecord] {
        let safelist = SafelistEngine(whitelist: whitelist, protectedCookies: protectedCookies)
        let engine = RuleEngine(trackerList: trackerList, now: now)
        var snapshot = SnapshotStore.load()
        var records: [CookieRecord] = []
        records.reserveCapacity(rawCookies.count)

        for raw in rawCookies {
            let browserAgnosticID = "\(raw.domain)|\(raw.name)|\(raw.path)"

            let protection = safelist.evaluate(
                domain: raw.domain,
                name: raw.name,
                path: raw.path,
                isSecure: raw.isSecure,
                isHttpOnly: raw.isHttpOnly,
                isSessionOnly: raw.isSessionOnly,
                creation: raw.creation,
                now: now
            )
            let classified = engine.classify(raw: raw, protection: protection)

            var firstSeen = raw.creation ?? now
            if let seen = snapshot.entries[browserAgnosticID] {
                firstSeen = seen.firstSeen
            }
            snapshot.recordObservation(
                browserAgnosticID,
                browser: raw.browser,
                valueHash: raw.valueHash,
                at: now,
                firstSeenFallback: firstSeen
            )
            let churn = snapshot.entries[browserAgnosticID]?.churnCounts?[raw.browser] ?? 0

            var category = classified.category
            var verdict = classified.verdict
            var reasoning = classified.reasoning

            if let aiCategory = raw.aiCategory, let aiVerdict = raw.aiVerdict, protection == .none {
                let judgement = LLMCookieJudgement(
                    domain: raw.domain,
                    name: raw.name,
                    category: aiCategory,
                    verdict: aiVerdict,
                    reasoning: raw.aiReasoning ?? ""
                )
                let surrogate = CookieRecord(
                    domain: raw.domain, name: raw.name, valueHash: "", browser: raw.browser, path: raw.path,
                    expiry: raw.expiry, isSecure: raw.isSecure, isHttpOnly: raw.isHttpOnly,
                    isSessionOnly: raw.isSessionOnly, firstSeen: firstSeen, lastSeen: now,
                    category: classified.category, verdict: classified.verdict,
                    reasoning: classified.reasoning, protection: protection
                )
                let outcome = AIConsensus.apply(judgement: judgement, to: surrogate)
                category = outcome.category
                verdict = outcome.verdict
                reasoning = outcome.reasoning
            }

            records.append(CookieRecord(
                domain: raw.domain,
                name: raw.name,
                valueHash: raw.valueHash ?? Hashing.cookieValueHash(domain: raw.domain, name: raw.name, path: raw.path),
                browser: raw.browser,
                path: raw.path,
                expiry: raw.expiry,
                isSecure: raw.isSecure,
                isHttpOnly: raw.isHttpOnly,
                isSessionOnly: raw.isSessionOnly,
                firstSeen: firstSeen,
                lastSeen: now,
                category: category,
                verdict: verdict,
                reasoning: reasoning,
                protection: protection,
                valueChurn: churn > 0 ? churn : nil
            ))
        }

        try? snapshot.save()
        return records
    }

    nonisolated static func persist(run: ScanRun) async throws {
        try JSONRunLog.write(run: run)
    }
}

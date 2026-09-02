import Foundation

let startedAt = Date()
let defaults = UserDefaults.standard

let protectedCookies = Set(ProtectedCookieStore.load().keys)
let domainRules = DomainRulesStore.load().rules

let (statuses, rawCookies) = await ScanService.scanSources(ScanService.buildSources())

var cookies = rawCookies
var aiUsed = false
var aiCount = 0
var aiSkipped: String?

if defaults.bool(forKey: "ollamaEnabled") {
    guard let trackerList = TrackerList() else {
        FileHandle.standardError.write(Data("CrumbAgent: tracker-domeinenlijst ontbreekt.\n".utf8))
        exit(1)
    }
    let result = await ScanService.classifyWithAI(
        rawCookies: cookies,
        trackerList: trackerList,
        model: defaults.string(forKey: "ollamaModel") ?? "llama3.1:8b",
        now: startedAt
    )
    cookies = result.cookies
    aiUsed = result.used
    aiCount = result.classifiedCount
    aiSkipped = result.skippedReason
}

let whitelist = Set(WhitelistStore.load().domains.map(WhitelistStore.normalizedDomain))
guard let trackerList = TrackerList() else {
    FileHandle.standardError.write(Data("CrumbAgent: tracker-domeinenlijst ontbreekt.\n".utf8))
    exit(1)
}
let records = await ScanService.buildRecords(
    rawCookies: cookies,
    whitelist: whitelist,
    trackerList: trackerList,
    now: startedAt,
    protectedCookies: protectedCookies,
    domainRules: domainRules
)

let run = ScanRun(
    startedAt: startedAt,
    finishedAt: Date(),
    sources: statuses,
    records: records,
    aiUsed: aiUsed,
    aiClassifiedCount: aiCount,
    aiSkippedReason: aiSkipped,
    origin: "agent"
)

do {
    try JSONRunLog.write(run: run)
} catch {
    FileHandle.standardError.write(Data("CrumbAgent: loggen mislukt: \(error)\n".utf8))
}

// Onderhoud: rapporten en back-ups niet onbeperkt laten groeien.
try? JSONRunLog.deleteLogs(olderThan: 90 * 24 * 60 * 60)
let backupRetentionDays = defaults.object(forKey: "backupRetentionDays") as? Int ?? 90
if backupRetentionDays > 0 {
    try? CookieBackupStore.deleteBackups(olderThan: TimeInterval(backupRetentionDays) * 86_400)
}

let autoCleanSettings = AutoCleanSettings.fromDefaults(defaults)
let autoCleanCandidates = AutoCleanEngine.candidates(in: run, settings: autoCleanSettings)
let thresholdSkipped = AutoCleanEngine.thresholdSkipped(candidates: autoCleanCandidates, settings: autoCleanSettings)
let cleaned = thresholdSkipped ? [] : await AutoCleanEngine.process(run: run, settings: autoCleanSettings)

let autoCleanDeleted = cleaned.filter { $0.result == "deleted" }.count
if autoCleanDeleted > 0 {
    let blocked = cleaned.filter { $0.result != "deleted" }.count
    var message = "Auto-clean: \(autoCleanDeleted) cookie(s) opgeruimd."
    if blocked > 0 { message += " \(blocked) geblokkeerd of mislukt." }
    Notifier.post(title: "Crumb", message: message)
} else if thresholdSkipped {
    Notifier.post(
        title: "Crumb",
        message: "Auto-clean overgeslagen: \(autoCleanCandidates.count) veilige cookies, drempel is \(autoCleanSettings.minSafeCookies)."
    )
}

struct AgentSummary: Codable {
    struct SourceSummary: Codable {
        let browser: String
        let scanned: Bool
        let cookies: Int
        let error: String?
    }
    let startedAt: Date
    let finishedAt: Date
    let scanned: Int
    let reviewSuggested: Int
    let safeToClean: Int
    let locked: Int
    let aiUsed: Bool
    let aiClassified: Int
    let autoCleanDeleted: Int
    let autoCleanFailed: Int
    let sources: [SourceSummary]
}

let summary = AgentSummary(
    startedAt: run.startedAt,
    finishedAt: run.finishedAt,
    scanned: records.count,
    reviewSuggested: records.filter { $0.verdict == .reviewSuggested }.count,
    safeToClean: records.filter { $0.verdict == .safeToClean }.count,
    locked: records.filter(\.protection.isLocked).count,
    aiUsed: aiUsed,
    aiClassified: aiCount,
    autoCleanDeleted: autoCleanDeleted,
    autoCleanFailed: cleaned.filter { $0.result != "deleted" }.count,
    sources: statuses.map {
        AgentSummary.SourceSummary(browser: $0.browser, scanned: $0.scanned, cookies: $0.cookieCount, error: $0.error)
    }
)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let data = try? encoder.encode(summary), let text = String(data: data, encoding: .utf8) {
    print(text)
}

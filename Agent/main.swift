import Foundation

let startedAt = Date()
let defaults = UserDefaults.standard

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
    now: startedAt
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

let autoCleanSettings = AutoCleanSettings.fromDefaults(defaults)
let cleaned = await AutoCleanEngine.process(run: run, settings: autoCleanSettings)

let autoCleanDeleted = cleaned.filter { $0.result == "deleted" }.count
if autoCleanDeleted > 0 {
    Notifier.post(title: "Crumb", message: "Auto-clean: \(autoCleanDeleted) cookie(s) opgeruimd.")
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

import Foundation

struct AutoCleanSettings: Sendable {
    var enabled: Bool = false
    var includeMarketingTracking: Bool = false
    var includeAnalytics: Bool = false
    var minAgeDays: Int = 30

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> AutoCleanSettings {
        AutoCleanSettings(
            enabled: defaults.bool(forKey: "autoCleanEnabled"),
            includeMarketingTracking: defaults.bool(forKey: "autoCleanMarketingTracking"),
            includeAnalytics: defaults.bool(forKey: "autoCleanAnalytics"),
            minAgeDays: defaults.object(forKey: "autoCleanMinAgeDays") as? Int ?? 30
        )
    }
}

enum AutoCleanEngine {
    static func candidates(in run: ScanRun, settings: AutoCleanSettings, now: Date = Date()) -> [CookieRecord] {
        guard settings.enabled else { return [] }
        let allowedCategories: Set<CookieCategory> = {
            var set: Set<CookieCategory> = []
            if settings.includeMarketingTracking { set.insert(.marketingTracking) }
            if settings.includeAnalytics { set.insert(.analytics) }
            return set
        }()
        guard !allowedCategories.isEmpty else { return [] }

        return run.records.filter { record in
            guard record.verdict == .safeToClean else { return false }
            guard !record.protection.isLocked else { return false }
            guard allowedCategories.contains(record.category) else { return false }
            let age = now.timeIntervalSince(record.firstSeen)
            return age >= TimeInterval(settings.minAgeDays) * 86_400
        }
    }

    static func process(run: ScanRun, settings: AutoCleanSettings, now: Date = Date()) async -> [AuditEntry] {
        let selected = candidates(in: run, settings: settings, now: now)
        guard !selected.isEmpty else { return [] }

        let results = await DeletionEngine.delete(selected)
        let entries = results.map { result in
            AuditEntry(
                timestamp: now,
                mode: "auto",
                browser: result.record.browser,
                domain: result.record.domain,
                name: result.record.name,
                path: result.record.path,
                category: result.record.category.rawValue,
                verdict: result.record.verdict.rawValue,
                reasoning: result.record.reasoning,
                result: result.success ? "deleted" : "failed",
                detail: result.detail
            )
        }
        try? AuditLog.append(entries)
        return entries
    }
}

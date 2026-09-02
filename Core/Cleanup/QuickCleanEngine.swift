import Foundation

enum QuickCleanPreset: String, CaseIterable, Identifiable, Sendable {
    case marketingTracking
    case staleAnalytics
    case allSafeToClean
    case unclassifiedNonEssential

    var id: String { rawValue }

    var title: String {
        switch self {
        case .marketingTracking:
            return "Tracking & Marketing"
        case .staleAnalytics:
            return "Oude Analytics (> 30d)"
        case .allSafeToClean:
            return "Alles Opschoonbaar"
        case .unclassifiedNonEssential:
            return "Onbekend & verlopen"
        }
    }

    var description: String {
        switch self {
        case .marketingTracking:
            return "Verwijdert advertentienetwerken en cross-site tracker cookies."
        case .staleAnalytics:
            return "Ruimt analysecookies op die al meer dan een maand oud zijn."
        case .allSafeToClean:
            return "Verwijdert cookies die unaniem als veilig zijn beoordeeld."
        case .unclassifiedNonEssential:
            return "Ruimt ongeclassificeerde cookies op die zijn verlopen of sessiegebonden — geen logins, geen beveiligde cookies."
        }
    }

    var systemImage: String {
        switch self {
        case .marketingTracking:
            return "target"
        case .staleAnalytics:
            return "clock.arrow.circlepath"
        case .allSafeToClean:
            return "sparkles"
        case .unclassifiedNonEssential:
            return "questionmark.folder"
        }
    }
}

enum QuickCleanEngine {
    static func candidates(
        for preset: QuickCleanPreset,
        in run: ScanRun,
        now: Date = Date()
    ) -> [CookieRecord] {
        run.records.filter { record in
            // Harde safelist blokkade geldt altijd; cookies met reviewOnly-
            // bescherming (mogelijk actieve sessie) nooit in bulk meenemen.
            guard !record.protection.isLocked else { return false }
            guard !record.protection.isReviewOnly else { return false }

            switch preset {
            case .marketingTracking:
                return record.category == .marketingTracking

            case .staleAnalytics:
                guard record.category == .analytics else { return false }
                let age = now.timeIntervalSince(record.firstSeen)
                return age >= 30 * 86_400

            case .allSafeToClean:
                return record.verdict == .safeToClean

            case .unclassifiedNonEssential:
                // Alleen ongeclassificeerde cookies die geen rol (meer) spelen:
                // verlopen of sessiegebonden, en nooit beveiligde cookies die
                // als sessie/auth kunnen fungeren.
                guard record.category == .thirdPartyUnknown || record.category == .unknown else {
                    return false
                }
                guard !record.isSecure || !record.isHttpOnly else { return false }
                if let expiry = record.expiry { return expiry < now }
                return record.isSessionOnly
            }
        }
    }

    static func runningBrowsers(for records: [CookieRecord]) -> [String] {
        let involved = Set(records.map(\.browser))
        return involved.filter { DeletionEngine.isBrowserRunning($0) }.sorted()
    }

    static func delete(
        records: [CookieRecord],
        preset: QuickCleanPreset
    ) async -> [DeletionResult] {
        let results = await DeletionEngine.delete(records)
        let entries: [AuditEntry] = results.map { result in
            AuditEntry(
                timestamp: Date(),
                mode: "quick_clean:\(preset.rawValue)",
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
        return results
    }
}

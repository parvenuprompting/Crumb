import Foundation

struct RuleEngine: Sendable {
    let trackerList: TrackerList
    let now: Date

    static let analyticsNames: Set<String> = [
        "_ga", "_gid", "_gat", "_gat_gtag", "_ga_", "_fbp", "_gcl_au", "_gcl_aw",
        "_hjid", "_hjincludedinstest", "_hjabsoluteuserinitsession",
        "amplitude_id", "ajs_anonymous_id", "ajs_group_id", "ajs_user_id",
        "mp_", "optimizelyenduserid", "ln_or", "rl_anonymous_id", "edu_cuid"
    ]

    static let analyticsAgeThreshold: TimeInterval = 30 * 24 * 60 * 60

    func classify(raw: RawCookie, protection: CookieProtection) -> (category: CookieCategory, verdict: CookieVerdict, reasoning: String) {
        switch protection {
        case .locked(let reason):
            return (.essential, .keep, reason)
        case .reviewOnly(let reason):
            let category = nonEssentialCategory(raw: raw)
            return (category, .reviewSuggested, reason)
        case .none:
            break
        }

        let category = nonEssentialCategory(raw: raw)
        switch category {
        case .marketingTracking:
            return (
                category,
                .safeToClean,
                "Bekend tracking-/advertentiedomein. De regellaag beslist dit zelf: dit is geen inlogcookie. Er wordt eerst een back-up gemaakt voordat hij weggaat."
            )
        case .analytics:
            if let creation = raw.creation, now.timeIntervalSince(creation) > Self.analyticsAgeThreshold {
                return (category, .safeToClean, "Analytics-cookie ouder dan 30 dagen. De regellaag beslist dit zelf; recente analytics blijven staan.")
            }
            return (category, .keep, "Analytics-cookie, recent aangemaakt — nog bewaren.")
        case .functional:
            return (category, .keep, "Beveiligde first-party cookie (secure + httpOnly) — waarschijnlijk functioneel.")
        default:
            return (.unknown, .keep, "Onvoldoende indicatie uit de regellaag; de AI kan dit cookie nader indelen.")
        }
    }

    func provisionalCategory(for raw: RawCookie) -> CookieCategory {
        nonEssentialCategory(raw: raw)
    }

    /// Cookies die de AI-laag mag beoordelen: alleen de onbekende. Bekende
    /// trackers en oude analytics beslist de regellaag zelf — daar is geen
    /// tweede ronde voor nodig (en een scan hoeft er dus ook niet op te wachten).
    func isAICandidate(_ raw: RawCookie) -> Bool {
        switch nonEssentialCategory(raw: raw) {
        case .unknown, .thirdPartyUnknown:
            return true
        default:
            return false
        }
    }

    private func nonEssentialCategory(raw: RawCookie) -> CookieCategory {
        // Beveiligde, persistente cookies zijn éérst functioneel: dat zijn de
        // inlogs. Stond de trackerlijst vooraan, dan werd een inlogcookie op een
        // domein dat ook in die lijst staat (sociaal, advertentieplatform) als
        // 'opschoonbaar' beoordeeld. Gevonden door de reviewer op 25-11-2026.
        if raw.isHttpOnly && raw.isSecure && !raw.isSessionOnly {
            return .functional
        }
        if Self.isAnalyticsName(raw.name) {
            return .analytics
        }
        if trackerList.isTracker(domain: raw.domain) {
            return .marketingTracking
        }
        return .unknown
    }

    static func isAnalyticsName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return analyticsNames.contains { pattern in
            pattern.hasSuffix("_") ? lower.hasPrefix(pattern) : lower == pattern
        }
    }
}

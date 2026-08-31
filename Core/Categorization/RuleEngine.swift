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
                .reviewSuggested,
                "Matcht bekende tracking/advertentie-domein. Advies volgt alleen uit de regellaag — bevestig handmatig (AI-laag volgt in latere versie)."
            )
        case .analytics:
            if let creation = raw.creation, now.timeIntervalSince(creation) > Self.analyticsAgeThreshold {
                return (category, .reviewSuggested, "Analytics-cookie ouder dan 30 dagen — opschoonkandidaat volgens regellaag.")
            }
            return (category, .keep, "Analytics-cookie, recent aangemaakt — nog bewaren.")
        case .functional:
            return (category, .keep, "Beveiligde first-party cookie (secure + httpOnly) — waarschijnlijk functioneel.")
        default:
            return (.unknown, .keep, "Onvoldoende indicatie uit regellaag; AI-classificatie volgt in een latere versie.")
        }
    }

    func provisionalCategory(for raw: RawCookie) -> CookieCategory {
        nonEssentialCategory(raw: raw)
    }

    private func nonEssentialCategory(raw: RawCookie) -> CookieCategory {
        if Self.isAnalyticsName(raw.name) {
            return .analytics
        }
        if trackerList.isTracker(domain: raw.domain) {
            return .marketingTracking
        }
        if raw.isHttpOnly && raw.isSecure && !raw.isSessionOnly {
            return .functional
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

import Foundation

/// Vertaalt de technische bescherming/verdict naar concrete, begrijpelijke
/// uitleg: waarom wordt een cookie niet verwijderd, waarom review, waarom wel.
enum ProtectionExplanation {
    static func explain(_ record: CookieRecord, now: Date = Date()) -> String {
        switch record.protection {
        case .locked(let reason):
            return "Beschermd: \(shortLockedReason(reason))"
        case .reviewOnly(let reason):
            return "Review vereist: \(shortReviewReason(reason))"
        case .none:
            break
        }

        switch record.verdict {
        case .safeToClean:
            return "Verwijderbaar: \(cleanableReason(record, now: now))"
        case .reviewSuggested:
            if record.reasoning.contains("niet bevestigen") {
                return "Niet verwijderd: AI en regellaag zijn het niet eens — beoordeel handmatig."
            }
            return "Review aanbevolen: \(shortReasoning(record.reasoning))"
        case .keep:
            return "Bewaard: \(shortReasoning(record.reasoning))"
        }
    }

    private static func shortLockedReason(_ reason: String) -> String {
        if reason.contains("Handmatig beschermd") { return "handmatig beschermd door jou" }
        if reason.contains("whitelist") { return "staat op je whitelist" }
        if let start = reason.range(of: "('"), let end = reason.range(of: "')") {
            let token = String(reason[start.upperBound..<end.lowerBound])
            if reason.contains("auth-patroon") { return "naam matcht sessiepatroon '\(token)'" }
            return "naam bevat '\(token)'"
        }
        if reason.contains("auth-prefix") { return "__Host-/__Secure- prefix (sessiecookie)" }
        return reason
    }

    private static func shortReviewReason(_ reason: String) -> String {
        if reason.contains("24 uur") { return "secure + httpOnly + jonger dan 24 uur — mogelijk actieve sessie" }
        return reason
    }

    private static func cleanableReason(_ record: CookieRecord, now: Date) -> String {
        var parts: [String] = []
        switch record.category {
        case .marketingTracking: parts.append("tracker")
        case .analytics: parts.append("analytics")
        case .thirdPartyUnknown: parts.append("onbekende third-party")
        default: break
        }
        let ageDays = now.timeIntervalSince(record.firstSeen) / 86_400
        if ageDays >= 30 { parts.append("ouder dan 30 dagen") }
        if record.valueChurn.map({ $0 >= 3 }) == true { parts.append("komt telkens terug") }
        parts.append("geen bescherming")
        return parts.joined(separator: ", ")
    }

    private static func shortReasoning(_ reasoning: String) -> String {
        reasoning
            .replacingOccurrences(of: "Regellaag en AI adviseren beide opschonen. ", with: "")
            .replacingOccurrences(of: "AI: ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

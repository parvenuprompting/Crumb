import Foundation

enum AIConsensus {
    struct Outcome: Equatable, Sendable {
        let category: CookieCategory
        let verdict: CookieVerdict
        let reasoning: String
    }

    /// Categorieën die het LLM zelf mag aandragen om 'safe' te ondersteunen.
    static let aiAllowedCategories: Set<CookieCategory> = [.marketingTracking, .thirdPartyUnknown, .analytics]

    /// Categorieën waarin de regel-laag zelf een cookie als opschoonkandidaat markeert.
    static let ruleAllowedCategories: Set<CookieCategory> = [.marketingTracking, .analytics]

    static func apply(
        judgement: LLMCookieJudgement,
        to record: CookieRecord
    ) -> Outcome {
        var category = judgement.category
        if category == .unknown {
            category = record.category
        }

        let baseReasoning = judgement.reasoning.isEmpty
            ? "AI-classificatie zonder uitleg."
            : judgement.reasoning

        switch judgement.verdict {
        case .keep:
            // Een regel-beslissing mag alleen teruggedraaid worden met een
            // positief signaal: het cookie ís volgens de AI functioneel of
            // essentieel (een inlog). "Weet ik niet" is geen reden om te bewaren.
            if record.verdict == .safeToClean {
                if category == .functional || category == .essential {
                    return Outcome(
                        category: category,
                        verdict: .keep,
                        reasoning: "AI ziet een functionele/inlog-cookie, dus bewaren. \(baseReasoning)"
                    )
                }
                return Outcome(
                    category: record.category,
                    verdict: .safeToClean,
                    reasoning: "Regellaag: opschonen. De AI noemt geen functionele categorie, dus dat advies blijft staan. AI: \(baseReasoning)"
                )
            }
            return Outcome(category: category, verdict: .keep, reasoning: "AI: \(baseReasoning)")
        case .review:
            if record.verdict == .safeToClean {
                return Outcome(
                    category: record.category,
                    verdict: .safeToClean,
                    reasoning: "Regellaag: opschonen (de AI twijfelt, maar noemt geen functionele categorie). AI: \(baseReasoning)"
                )
            }
            return Outcome(category: category, verdict: .reviewSuggested, reasoning: "AI: \(baseReasoning)")
        case .safe:
            guard aiAllowedCategories.contains(category), !record.protection.isLocked else {
                return Outcome(
                    category: category,
                    verdict: .reviewSuggested,
                    reasoning: "AI adviseert opschonen, maar categorie '\(category.displayName)' komt daar niet voor in aanmerking — afgezet naar review. \(baseReasoning)"
                )
            }
            // De regellaag beslist zelf over bekende trackers en oude analytics;
            // bij onbekende cookies blijft een tweede bevestiging nodig.
            if record.verdict == .safeToClean {
                return Outcome(
                    category: category,
                    verdict: .safeToClean,
                    reasoning: "Regellaag en AI adviseren beide opschonen. AI: \(baseReasoning)"
                )
            }
            guard ruleAllowedCategories.contains(record.category), record.verdict == .reviewSuggested else {
                return Outcome(
                    category: category,
                    verdict: .reviewSuggested,
                    reasoning: "AI adviseert opschonen, maar de regel-laag kan dit niet bevestigen (categorie '\(record.category.displayName)', advies '\(record.verdict.displayName)') — afgezet naar review. \(baseReasoning)"
                )
            }
            return Outcome(
                category: category,
                verdict: .safeToClean,
                reasoning: "Regellaag en AI adviseren beide opschonen. AI: \(baseReasoning)"
            )
        }
    }
}

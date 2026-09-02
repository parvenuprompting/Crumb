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
            return Outcome(category: category, verdict: .keep, reasoning: "AI: \(baseReasoning)")
        case .review:
            return Outcome(category: category, verdict: .reviewSuggested, reasoning: "AI: \(baseReasoning)")
        case .safe:
            guard aiAllowedCategories.contains(category), !record.protection.isLocked else {
                return Outcome(
                    category: category,
                    verdict: .reviewSuggested,
                    reasoning: "AI adviseert opschonen, maar categorie '\(category.displayName)' komt daar niet voor in aanmerking — afgezet naar review. \(baseReasoning)"
                )
            }
            // Dubbele goedkeuring: de regel-laag moet het cookie zelf als
            // opschoonkandidaat hebben gemarkeerd. Alleen het LLM is nooit
            // genoeg — zonder bevestiging uit de regel-laag blijft het bij review.
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

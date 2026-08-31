import Foundation

enum AIConsensus {
    struct Outcome: Equatable, Sendable {
        let category: CookieCategory
        let verdict: CookieVerdict
        let reasoning: String
    }

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
            let allowedCategories: Set<CookieCategory> = [.marketingTracking, .thirdPartyUnknown, .analytics]
            guard allowedCategories.contains(category), !record.protection.isLocked else {
                return Outcome(
                    category: category,
                    verdict: .reviewSuggested,
                    reasoning: "AI adviseert opschonen, maar categorie '\(category.displayName)' komt daar niet voor in aanmerking — afgezet naar review. \(baseReasoning)"
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

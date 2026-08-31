import XCTest
@testable import Crumb

final class AIConsensusTests: XCTestCase {
    private func record(
        category: CookieCategory = .unknown,
        verdict: CookieVerdict = .keep,
        protection: CookieProtection = .none
    ) -> CookieRecord {
        CookieRecord(
            domain: "example.com",
            name: "c",
            valueHash: "abc",
            browser: "Chrome",
            path: "/",
            expiry: nil,
            isSecure: false,
            isHttpOnly: false,
            isSessionOnly: false,
            firstSeen: Date(timeIntervalSince1970: 1),
            lastSeen: Date(timeIntervalSince1970: 2),
            category: category,
            verdict: verdict,
            reasoning: "",
            protection: protection
        )
    }

    private func judgement(
        category: CookieCategory,
        verdict: LLMVerdict
    ) -> LLMCookieJudgement {
        LLMCookieJudgement(domain: "example.com", name: "c", category: category, verdict: verdict, reasoning: "test")
    }

    func testKeepStaysKeep() {
        let outcome = AIConsensus.apply(judgement: judgement(category: .functional, verdict: .keep), to: record())
        XCTAssertEqual(outcome.verdict, .keep)
        XCTAssertTrue(outcome.reasoning.hasPrefix("AI:"))
    }

    func testReviewBecomesReviewSuggested() {
        let outcome = AIConsensus.apply(judgement: judgement(category: .functional, verdict: .review), to: record())
        XCTAssertEqual(outcome.verdict, .reviewSuggested)
    }

    func testSafeOnMarketingTrackingBecomesSafeToClean() {
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .marketingTracking, verdict: .safe),
            to: record(category: .unknown)
        )
        XCTAssertEqual(outcome.verdict, .safeToClean)
        XCTAssertTrue(outcome.reasoning.contains("beide"))
    }

    func testSafeOnEssentialIsDowngraded() {
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .essential, verdict: .safe),
            to: record()
        )
        XCTAssertEqual(outcome.verdict, .reviewSuggested)
    }

    func testSafeOnSafelistedIsDowngraded() {
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .marketingTracking, verdict: .safe),
            to: record(protection: .locked("whitelist"))
        )
        XCTAssertEqual(outcome.verdict, .reviewSuggested)
    }

    func testUnknownLLMCategoryFallsBackToRecordCategory() {
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .unknown, verdict: .keep),
            to: record(category: .functional)
        )
        XCTAssertEqual(outcome.category, .functional)
    }

    func testOllamaCategoryMapping() {
        XCTAssertEqual(OllamaClient.mapCategory("marketing"), .marketingTracking)
        XCTAssertEqual(OllamaClient.mapCategory("Advertising"), .marketingTracking)
        XCTAssertEqual(OllamaClient.mapCategory("essentieel"), .essential)
        XCTAssertEqual(OllamaClient.mapCategory("third_party"), .thirdPartyUnknown)
        XCTAssertEqual(OllamaClient.mapCategory("onzin"), .unknown)
    }

    func testJudgementParsingTolerant() {
        let content = """
        Hier is mijn analyse:
        {"cookies":[{"domain":"Ad1.example","name":"uid","category":"marketing","verdict":"safe","reasoning":"advertentie-id"},{"domain":"shop.example","name":"cart","category":"functional","verdict":"keep","reasoning":"winkelmand"}]}
        """
        let judgements = OllamaClient.parseJudgements(content: content)
        XCTAssertEqual(judgements.count, 2)
        XCTAssertEqual(judgements[0].verdict, .safe)
        XCTAssertEqual(judgements[1].verdict, .keep)
    }
}

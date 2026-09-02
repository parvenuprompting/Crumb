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

    func testSafeRequiresRuleLayerAgreement() {
        // Regel-laag zegt unknown/keep: AI alleen is nooit genoeg.
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .marketingTracking, verdict: .safe),
            to: record(category: .unknown, verdict: .keep)
        )
        XCTAssertEqual(outcome.verdict, .reviewSuggested)
        XCTAssertTrue(outcome.reasoning.contains("regel-laag"))
        XCTAssertFalse(outcome.reasoning.contains("beide opschonen"))
    }

    func testSafeOnRuleLayerTrackerCandidateBecomesSafeToClean() {
        // Regel-laag markeert als opschoonkandidaat, AI bevestigt: safeToClean.
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .marketingTracking, verdict: .safe),
            to: record(category: .marketingTracking, verdict: .reviewSuggested)
        )
        XCTAssertEqual(outcome.verdict, .safeToClean)
        XCTAssertTrue(outcome.reasoning.contains("beide"))
    }

    func testSafeOnStaleAnalyticsCandidateBecomesSafeToClean() {
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .analytics, verdict: .safe),
            to: record(category: .analytics, verdict: .reviewSuggested)
        )
        XCTAssertEqual(outcome.verdict, .safeToClean)
    }

    func testSafeOnRecentAnalyticsIsDowngraded() {
        // Regel-laag houdt recente analytics bij ('keep'): AI kan dat niet overrulen.
        let outcome = AIConsensus.apply(
            judgement: judgement(category: .analytics, verdict: .safe),
            to: record(category: .analytics, verdict: .keep)
        )
        XCTAssertEqual(outcome.verdict, .reviewSuggested)
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

    func testBuildBatchesAreDeterministicAndSorted() {
        let cookies = (0..<30).map { i in
            CookiePromptInput(
                domain: "d\(i % 10).com",
                name: "n\(i)",
                isSecure: false,
                isHttpOnly: false,
                isSessionOnly: false,
                hasExpiry: false,
                expiresInSeconds: nil,
                browser: "Chrome"
            )
        }
        let batches1 = OllamaClient.buildBatches(cookies: cookies, cookiesPerBatch: 3, maxBatches: 5)
        let batches2 = OllamaClient.buildBatches(cookies: cookies.reversed(), cookiesPerBatch: 3, maxBatches: 5)

        XCTAssertEqual(batches1.count, 5)
        XCTAssertEqual(batches1.map { $0.map(\.name) }, batches2.map { $0.map(\.name) })
        // Elk domein blijft binnen één batch, en batches zijn op domein gesorteerd.
        for batch in batches1 {
            XCTAssertEqual(Set(batch.map(\.domain)).count, 1)
        }
        let domains = batches1.compactMap(\.first?.domain)
        XCTAssertEqual(domains, domains.sorted())
    }

    func testBuildBatchesCoversAllCookiesUnderCap() {
        // 4 cookies per domein, 3 per batch: elk domein splitst in 3+1,
        // alle cookies blijven binnen de cap.
        let cookies = (0..<12).map { i in
            CookiePromptInput(
                domain: "d\(i % 3).com",
                name: "n\(i)",
                isSecure: false,
                isHttpOnly: false,
                isSessionOnly: false,
                hasExpiry: false,
                expiresInSeconds: nil,
                browser: "Chrome"
            )
        }
        let batches = OllamaClient.buildBatches(cookies: cookies, cookiesPerBatch: 3, maxBatches: 10)
        XCTAssertEqual(batches.flatMap { $0 }.count, 12)
        XCTAssertEqual(batches.count, 6)
        XCTAssertTrue(batches.allSatisfy { (1...3).contains($0.count) })
        XCTAssertTrue(batches.allSatisfy { Set($0.map(\.domain)).count == 1 })
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

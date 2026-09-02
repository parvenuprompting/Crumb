import XCTest
@testable import Crumb

final class OllamaClientTests: XCTestCase {
    func testParsesBareArrayResponse() throws {
        let content = """
        [{"domain":"a.com","name":"n","category":"analytics","verdict":"keep","reasoning":"r"}]
        """
        let judgements = OllamaClient.parseJudgements(content: content)
        XCTAssertEqual(judgements.count, 1)
        XCTAssertEqual(judgements[0].category, .analytics)
        XCTAssertEqual(judgements[0].verdict, .keep)
    }

    func testInvalidVerdictsAreFilteredOut() {
        let content = """
        {"cookies":[{"domain":"a.com","name":"n","verdict":"maybe"},{"domain":"b.com","name":"m","verdict":"safe"}]}
        """
        let judgements = OllamaClient.parseJudgements(content: content)
        XCTAssertEqual(judgements.count, 1)
        XCTAssertEqual(judgements[0].domain, "b.com")
    }

    func testTextWithoutJSONYieldsNothing() {
        XCTAssertTrue(OllamaClient.parseJudgements(content: "geen json hier").isEmpty)
        XCTAssertTrue(OllamaClient.parseJudgements(content: "").isEmpty)
    }

    func testEscapingForOsascript() {
        XCTAssertEqual(Notifier.escaped("say \"hi\" \\ now"), "say 'hi'  now")
        XCTAssertEqual(Notifier.escaped("plain tekst"), "plain tekst")
        XCTAssertEqual(Notifier.escaped(""), "")
    }
}

import XCTest
@testable import Crumb

final class SafelistEngineTests: XCTestCase {
    private let engine = SafelistEngine(whitelist: ["ing.nl", "work-sso.example"])

    private func evaluate(
        domain: String = "example.com",
        name: String = "prefs",
        isSecure: Bool = false,
        isHttpOnly: Bool = false,
        isSessionOnly: Bool = false,
        creation: Date? = nil,
        now: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> CookieProtection {
        engine.evaluate(
            domain: domain,
            name: name,
            isSecure: isSecure,
            isHttpOnly: isHttpOnly,
            isSessionOnly: isSessionOnly,
            creation: creation,
            now: now
        )
    }

    func testAuthPrefixIsLocked() {
        XCTAssertEqual(evaluate(name: "__Secure-sessionid"), .locked("Naam met auth-prefix (__Secure-) — sessiecookie."))
        XCTAssertEqual(evaluate(name: "__Host-token"), .locked("Naam met auth-prefix (__Host-) — sessiecookie."))
    }

    func testAuthCompoundIsLocked() {
        if case .locked = evaluate(name: "sessionid") {} else {
            XCTFail("sessionid moet vergrendeld zijn")
        }
        if case .locked = evaluate(name: "my_auth_token") {} else {
            XCTFail("auth_token moet vergrendeld zijn")
        }
    }

    func testExactTokenIsLocked() {
        if case .locked = evaluate(name: "SID") {} else {
            XCTFail("SID moet vergrendeld zijn")
        }
        if case .locked = evaluate(name: "csrftoken") {} else {
            XCTFail("csrftoken moet vergrendeld zijn")
        }
    }

    func testInnocentNamesAreNotLocked() {
        XCTAssertEqual(evaluate(name: "considered_settings"), .none)
        XCTAssertEqual(evaluate(name: "theme_sidebar"), .none)
        XCTAssertEqual(evaluate(name: "visited_pages"), .none)
    }

    func testWhitelistMatchesSuffix() {
        if case .locked = evaluate(domain: "www.ing.nl", name: "anything") {} else {
            XCTFail("www.ing.nl moet via whitelist beschermd zijn")
        }
        if case .locked = evaluate(domain: "ing.nl", name: "anything") {} else {
            XCTFail("ing.nl moet via whitelist beschermd zijn")
        }
        XCTAssertEqual(evaluate(domain: "noting.nl", name: "anything"), .none)
        XCTAssertEqual(evaluate(domain: "work-sso.example", name: "anything").isLocked, true)
    }

    func testRecentSecureSessionIsReviewOnly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let protection = evaluate(
            isSecure: true,
            isHttpOnly: true,
            creation: now.addingTimeInterval(-3600),
            now: now
        )
        XCTAssertEqual(protection.isReviewOnly, true)
    }

    func testOlderSecureSessionIsNotRestricted() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let protection = evaluate(
            isSecure: true,
            isHttpOnly: true,
            creation: now.addingTimeInterval(-3 * 24 * 60 * 60),
            now: now
        )
        XCTAssertEqual(protection, .none)
    }

    func testSessionOnlyCookieIsNotFlaggedAsRecentSession() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let protection = evaluate(
            isSecure: true,
            isHttpOnly: true,
            isSessionOnly: true,
            creation: now.addingTimeInterval(-3600),
            now: now
        )
        XCTAssertEqual(protection, .none)
    }

    func testRecentSessionWindowBoundary() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let justInside = evaluate(
            isSecure: true,
            isHttpOnly: true,
            creation: now.addingTimeInterval(-23 * 60 * 60),
            now: now
        )
        let justOutside = evaluate(
            isSecure: true,
            isHttpOnly: true,
            creation: now.addingTimeInterval(-25 * 60 * 60),
            now: now
        )
        XCTAssertEqual(justInside.isReviewOnly, true)
        XCTAssertEqual(justOutside, .none)
    }
}

final class WhitelistNormalizationTests: XCTestCase {
    func testURLInputIsReducedToHost() {
        XCTAssertEqual(WhitelistStore.normalizedDomain("https://bank.nl/login"), "bank.nl")
        XCTAssertEqual(WhitelistStore.normalizedDomain("https://www.bank.nl/x?y=1#z"), "bank.nl")
        XCTAssertEqual(WhitelistStore.normalizedDomain("bank.nl/foo"), "bank.nl")
        XCTAssertEqual(WhitelistStore.normalizedDomain("bank.nl/"), "bank.nl")
        XCTAssertEqual(WhitelistStore.normalizedDomain("http://ing.nl:443"), "ing.nl")
        XCTAssertEqual(WhitelistStore.normalizedDomain("ing.nl:8080"), "ing.nl")
    }

    func testCasingDotsAndWhitespace() {
        XCTAssertEqual(WhitelistStore.normalizedDomain("WWW.Example.COM"), "example.com")
        XCTAssertEqual(WhitelistStore.normalizedDomain(".adnxs.com"), "adnxs.com")
        XCTAssertEqual(WhitelistStore.normalizedDomain("  ing.nl  "), "ing.nl")
        XCTAssertEqual(WhitelistStore.normalizedDomain("ing.nl"), "ing.nl")
        XCTAssertEqual(WhitelistStore.normalizedDomain(""), "")
    }

    func testIPv6HostIsNotBroken() {
        XCTAssertEqual(WhitelistStore.normalizedDomain("fe80::1"), "fe80::1")
    }

    func testValidation() {
        XCTAssertTrue(WhitelistStore.isValidWhitelistDomain("bank.nl"))
        XCTAssertFalse(WhitelistStore.isValidWhitelistDomain(""))
        XCTAssertFalse(WhitelistStore.isValidWhitelistDomain("notadomain"))
        XCTAssertFalse(WhitelistStore.isValidWhitelistDomain("bank.nl/foo"))
        XCTAssertFalse(WhitelistStore.isValidWhitelistDomain("bank.nl:443"))
        XCTAssertFalse(WhitelistStore.isValidWhitelistDomain("bank .nl"))
    }
}

@MainActor
final class WhitelistModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WhitelistStore.overrideFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-tests-whitelist-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: WhitelistStore.fileURL)
        WhitelistStore.overrideFileURL = nil
        super.tearDown()
    }

    func testAddNormalizesURLInput() {
        let model = WhitelistModel()
        XCTAssertNil(model.add("https://bank.nl/login"))
        XCTAssertTrue(model.domains.contains("bank.nl"))
    }

    func testAddRejectsInputWithoutDomain() {
        let model = WhitelistModel()
        XCTAssertNotNil(model.add("notadomain"))
        XCTAssertNotNil(model.add("   "))
        XCTAssertTrue(model.domains.isEmpty)
    }

    func testAddAcceptsURLWithPath() {
        let model = WhitelistModel()
        XCTAssertNil(model.add("bank.nl/foo"))
        XCTAssertEqual(model.domains, ["bank.nl"])
    }

    func testAddRejectsDuplicateAfterNormalization() {
        let model = WhitelistModel()
        XCTAssertNil(model.add("bank.nl"))
        XCTAssertNotNil(model.add("www.bank.nl"))
        XCTAssertEqual(model.domains, ["bank.nl"])
    }
}

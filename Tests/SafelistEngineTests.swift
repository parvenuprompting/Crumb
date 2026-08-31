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

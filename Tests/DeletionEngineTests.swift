import XCTest
@testable import Crumb

final class DeletionEngineTests: XCTestCase {
    private func record(
        browser: String = "Chrome",
        protection: CookieProtection = .none
    ) -> CookieRecord {
        CookieRecord(
            domain: "ads.example", name: "uid", valueHash: "h", browser: browser, path: "/",
            expiry: nil, isSecure: false, isHttpOnly: false, isSessionOnly: false,
            firstSeen: Date(timeIntervalSince1970: 1), lastSeen: Date(timeIntervalSince1970: 2),
            category: .marketingTracking, verdict: .safeToClean, reasoning: "", protection: protection
        )
    }

    func testLockedCookieIsNeverDeletable() {
        let gate = DeletionEngine.canDelete(record(protection: .locked("whitelist")))
        XCTAssertFalse(gate.allowed)
        XCTAssertEqual(gate.reason, "Geblokkeerd door safelist.")
    }

    func testSafariDeletionIsBlockedWithReason() {
        let gate = DeletionEngine.canDelete(record(browser: "Safari"))
        XCTAssertFalse(gate.allowed)
        XCTAssertTrue(gate.reason?.contains("Safari") == true)
    }

    func testUnprotectedDeletableBrowsers() {
        XCTAssertTrue(DeletionEngine.canDelete(record(browser: "Chrome")).allowed)
        XCTAssertTrue(DeletionEngine.canDelete(record(browser: "Brave")).allowed)
        XCTAssertTrue(DeletionEngine.canDelete(record(browser: "Firefox")).allowed)
    }

    func testUnknownBrowsersHaveNoStores() {
        XCTAssertTrue(DeletionEngine.stores(for: "Safari").isEmpty)
        XCTAssertTrue(DeletionEngine.stores(for: "Onbekend").isEmpty)
    }
}

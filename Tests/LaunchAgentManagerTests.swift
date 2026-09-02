import XCTest
@testable import Crumb

final class LaunchAgentManagerTests: XCTestCase {
    func testPlistContentsIsValidPropertyList() throws {
        let contents = LaunchAgentManager.plistContents(
            agentBinaryPath: "/Applications/Crumb.app/Contents/MacOS/CrumbAgent",
            logPath: "/Users/test/Library/Logs/Crumb/agent.log"
        )

        let data = try XCTUnwrap(contents.data(using: .utf8))
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["Label"] as? String, "nl.tiendo.crumb.agent")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["StartInterval"] as? Int, 10800)
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            ["/Applications/Crumb.app/Contents/MacOS/CrumbAgent"]
        )
        XCTAssertEqual(plist["StandardOutPath"] as? String, "/Users/test/Library/Logs/Crumb/agent.log")
        XCTAssertEqual(plist["StandardErrorPath"] as? String, "/Users/test/Library/Logs/Crumb/agent.log")
    }
}

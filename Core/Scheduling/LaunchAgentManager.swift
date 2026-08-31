import Foundation

enum LaunchAgentManager {
    static let label = "nl.tiendo.crumb.agent"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var agentLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Crumb/agent.log")
    }

    static var agentBinaryURL: URL? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        return executableURL.deletingLastPathComponent().appendingPathComponent("CrumbAgent")
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install() throws {
        guard let agentBinaryURL, FileManager.default.fileExists(atPath: agentBinaryURL.path) else {
            throw CookieScanError.readFailed("CrumbAgent-binary niet gevonden in de app-bundle.")
        }
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: agentLogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(agentBinaryURL.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>10800</integer>
            <key>StandardOutPath</key>
            <string>\(agentLogURL.path)</string>
            <key>StandardErrorPath</key>
            <string>\(agentLogURL.path)</string>
        </dict>
        </plist>
        """
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        _ = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
            ?? runLaunchctl(["load", plistURL.path])
    }

    static func uninstall() {
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
            ?? runLaunchctl(["unload", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func runLaunchctl(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

import Foundation

/// Stelt macOS-gebruikersnotificaties op via osascript — werkt ook vanuit de
/// LaunchAgent (CLI-binary zonder bundel-ID, waar UNUserNotificationCenter
/// niet beschikbaar is).
enum Notifier {
    @discardableResult
    static func post(title: String, message: String) -> Bool {
        let script = "display notification \"\(escaped(message))\" with title \"\(escaped(title))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func escaped(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\"", with: "'")
    }
}

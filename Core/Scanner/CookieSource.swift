import Foundation

protocol CookieSource: Sendable {
    var browserName: String { get }
    var isInstalled: Bool { get }
    func scan() throws -> [RawCookie]
}

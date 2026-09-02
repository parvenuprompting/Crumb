import Foundation
import CryptoKit

enum Hashing {
    static func shortHash(_ input: String) -> String {
        shortHash(Data(input.utf8))
    }

    static func shortHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Identiteits-hash: duidt het cookie aan, zegt niets over de waarde.
    static func cookieValueHash(domain: String, name: String, path: String) -> String {
        shortHash("\(domain)|\(name)|\(path)")
    }
}

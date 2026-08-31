import Foundation
import CryptoKit

enum Hashing {
    static func shortHash(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func cookieValueHash(domain: String, name: String, path: String) -> String {
        shortHash("\(domain)|\(name)|\(path)")
    }
}

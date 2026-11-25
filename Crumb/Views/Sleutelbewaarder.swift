import Foundation
import Security

/// De synchronisatiesleutel hoort niet in een gewoon instellingenbestand.
/// Klein en zonder toeters: één sleutel per account, in de sleutelhanger.
enum Sleutelbewaarder {

    private static let dienst = "nl.tiendo.crumb.sporen"

    @discardableResult
    static func bewaar(_ waarde: String, voor account: String) -> Bool {
        let data = Data(waarde.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var nieuw = query
        nieuw[kSecValueData as String] = data
        nieuw[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(nieuw as CFDictionary, nil) == errSecSuccess
    }

    static func lees(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultaat: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &resultaat) == errSecSuccess,
              let data = resultaat as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func verwijder(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

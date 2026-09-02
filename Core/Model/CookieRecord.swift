import Foundation

enum CookieCategory: String, Codable, CaseIterable, Sendable {
    case essential
    case functional
    case analytics
    case marketingTracking
    case thirdPartyUnknown
    case unknown

    var displayName: String {
        switch self {
        case .essential: return "Essentieel"
        case .functional: return "Functioneel"
        case .analytics: return "Analytics"
        case .marketingTracking: return "Marketing/tracking"
        case .thirdPartyUnknown: return "Third-party (onbekend)"
        case .unknown: return "Onbekend"
        }
    }
}

enum CookieVerdict: String, Codable, CaseIterable, Sendable {
    case keep
    case reviewSuggested
    case safeToClean

    var displayName: String {
        switch self {
        case .keep: return "Bewaren"
        case .reviewSuggested: return "Review aanbevolen"
        case .safeToClean: return "Opschoonbaar"
        }
    }
}

enum CookieProtection: Codable, Hashable, Sendable {
    case locked(String)
    case reviewOnly(String)
    case none

    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    var isReviewOnly: Bool {
        if case .reviewOnly = self { return true }
        return false
    }
}

struct CookieRecord: Identifiable, Codable, Hashable, Sendable {
    let domain: String
    let name: String
    /// Bij Chromium de hash van de encrypted_value-blob (zonder te ontsleutelen);
    /// anders een identiteits-hash over domein|naam|pad.
    let valueHash: String
    let browser: String
    let path: String
    let expiry: Date?
    let isSecure: Bool
    let isHttpOnly: Bool
    let isSessionOnly: Bool
    let firstSeen: Date
    let lastSeen: Date
    var category: CookieCategory
    var verdict: CookieVerdict
    var reasoning: String
    var protection: CookieProtection
    /// Aantal keer dat de cookie-waarde (per browser) is veranderd sinds de
    /// eerste waarneming. nil bij cookies waarvoor geen waarde-hash beschikbaar is.
    var valueChurn: Int? = nil

    var id: String {
        CookieRecord.identity(browser: browser, domain: domain, name: name, path: path)
    }

    static func identity(browser: String, domain: String, name: String, path: String) -> String {
        "\(browser)|\(domain)|\(name)|\(path)"
    }
}

struct RawCookie: Sendable {
    var domain: String
    var name: String
    var path: String
    var expiry: Date?
    var creation: Date?
    var isSecure: Bool
    var isHttpOnly: Bool
    var isSessionOnly: Bool
    var browser: String = ""
    /// Hash van de versleutelde cookie-waarde (Chromium), indien beschikbaar —
    /// de waarde zelf wordt nooit gelezen.
    var valueHash: String? = nil
    var aiCategory: CookieCategory?
    var aiVerdict: LLMVerdict?
    var aiReasoning: String?
}

enum CookieScanError: LocalizedError {
    case fullDiskAccessRequired(path: String)
    case storeNotFound
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .fullDiskAccessRequired(let path):
            return "Volledige Schijftoegang vereist om \(path) te lezen."
        case .storeNotFound:
            return "Cookie-opslag niet gevonden."
        case .readFailed(let detail):
            return "Kon cookie-opslag niet lezen: \(detail)"
        }
    }
}

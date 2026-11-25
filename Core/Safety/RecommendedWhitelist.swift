import Foundation

/// Diensten die de gebruiker dagelijks gebruikt. Eén klik zet ze op de
/// whitelist; daarna komen ze nooit meer in een verwijderlijst terecht —
/// ook niet via "alles opschonen" of de automatische schoonmaak, want de
/// safelist blokkeert ze vóór elk advies.
///
/// De lijst is bewust kort en per groep: wat je elke dag inlogt, hoort
/// beschermd te zijn; de rest mag weg.
enum RecommendedWhitelist {

    struct Group: Identifiable, Sendable {
        let title: String
        let domains: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Google", domains: ["google.com", "youtube.com"]),
        Group(title: "AI", domains: ["claude.ai", "chatgpt.com", "openai.com", "openrouter.ai", "nousresearch.com"]),
        Group(title: "Sociaal", domains: ["x.com", "instagram.com", "tiktok.com"]),
        Group(title: "Muziek & beeld", domains: ["suno.com", "bandlab.com", "capcut.com", "openart.ai", "higgsfield.ai"]),
        Group(title: "Werk & infra", domains: ["github.com", "netlify.com", "mijndomein.nl"]),
        Group(title: "Overig", domains: ["funda.nl", "wetransfer.com", "indeed.com"]),
        Group(title: "Eigen omgeving", domains: ["tail214c32.ts.net"])
    ]

    /// Alle domeinen, plat en zonder dubbelen — in de volgorde van de groepen.
    static var allDomains: [String] {
        var gezien = Set<String>()
        var uit: [String] = []
        for group in groups {
            for domain in group.domains where gezien.insert(domain).inserted {
                uit.append(domain)
            }
        }
        return uit
    }

    /// Wat er nog niet op de whitelist staat.
    static func missing(from bestaand: [String]) -> [String] {
        let genormaliseerd = Set(bestaand.map(WhitelistStore.normalizedDomain))
        return allDomains.filter { !genormaliseerd.contains($0) }
    }
}

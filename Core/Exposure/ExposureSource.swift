import Foundation

/// Een bron waar je eigen naam kan opduiken. De app opent de bron met jouw
/// naam erin — hij scrapet niets en stuurt niets naar een derde partij.
public enum ExposureCategory: String, Codable, CaseIterable, Sendable {
    case zoekmachine
    case beroep
    case sociaal
    case databroker

    public var titel: String {
        switch self {
        case .zoekmachine: return "Zoekmachine"
        case .beroep: return "Werk en code"
        case .sociaal: return "Sociaal"
        case .databroker: return "Databroker"
        }
    }
}

public struct ExposureSource: Identifiable, Hashable, Sendable {
    public let id: String
    public let naam: String
    public let categorie: ExposureCategory
    /// Bevat `{naam}` en mag `{plaats}` bevatten.
    public let urlTemplate: String
    public let uitleg: String
    /// Hoe je bij deze bron om verwijdering vraagt — in gewone taal.
    public let verwijderRoute: String

    public init(id: String, naam: String, categorie: ExposureCategory,
                urlTemplate: String, uitleg: String, verwijderRoute: String) {
        self.id = id
        self.naam = naam
        self.categorie = categorie
        self.urlTemplate = urlTemplate
        self.uitleg = uitleg
        self.verwijderRoute = verwijderRoute
    }

    /// De link die je zelf opent. Leeg of alleen spaties geeft nil: geen halve zoekopdracht.
    public func url(naam: String, plaats: String? = nil) -> URL? {
        let schoneNaam = naam.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !schoneNaam.isEmpty else { return nil }
        let schonePlaats = (plaats ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var tekst = urlTemplate.replacingOccurrences(of: "{naam}", with: Self.codeer(schoneNaam))
        if tekst.contains("{plaats}") {
            tekst = tekst.replacingOccurrences(of: "{plaats}",
                                               with: schonePlaats.isEmpty ? "" : Self.codeer(schonePlaats))
        }
        // Een lege plaats mag geen los plusteken of lege parameter achterlaten.
        while tekst.contains("++") { tekst = tekst.replacingOccurrences(of: "++", with: "+") }
        if tekst.hasSuffix("+") { tekst.removeLast() }
        if tekst.hasSuffix("=") { tekst.removeLast() }
        return URL(string: tekst)
    }

    /// Procentcodering die ook "ë" en spaties goed doet, zonder dubbele codering.
    static func codeer(_ waarde: String) -> String {
        var toegestaan = CharacterSet.alphanumerics
        toegestaan.insert(charactersIn: "-._~")
        return waarde.addingPercentEncoding(withAllowedCharacters: toegestaan) ?? waarde
    }
}

public enum ExposureCatalog {

    /// Alleen bronnen die bestaan en waarvan de zoek-URL echt antwoordt.
    /// Volgorde = volgorde waarin de app ze toont.
    public static let bronnen: [ExposureSource] = [
        ExposureSource(
            id: "google", naam: "Google", categorie: .zoekmachine,
            urlTemplate: "https://www.google.com/search?q=%22{naam}%22+{plaats}",
            uitleg: "De eerste plek waar iemand met je naam begint. Let op de snippets: daar staat vaak je woonplaats of werkgever al in.",
            verwijderRoute: "Verwijderen van een zoekresultaat gaat via Google's hulpmiddel 'Resultaten over jou' (mijn activiteit) of via een verzoek aan de site zelf."),
        ExposureSource(
            id: "bing", naam: "Bing", categorie: .zoekmachine,
            urlTemplate: "https://www.bing.com/search?q=%22{naam}%22+{plaats}",
            uitleg: "Bing vult zijn index uit andere bronnen dan Google; wat daar staat, staat vaak ook in Copilot-antwoorden.",
            verwijderRoute: "Bing heeft een formulier voor het verwijderen van inhoud; de onderliggende pagina moet je bij de site zelf wegkrijgen."),
        ExposureSource(
            id: "duckduckgo", naam: "DuckDuckGo", categorie: .zoekmachine,
            urlTemplate: "https://duckduckgo.com/?q=%22{naam}%22+{plaats}",
            uitleg: "DuckDuckGo bouwt zijn index grotendeels uit Bing — verdwijnt het bij de bron, dan verdwijnt het hier vanzelf.",
            verwijderRoute: "Geen eigen index: verwijderen doe je bij de bron of via Bing."),
        ExposureSource(
            id: "linkedin", naam: "LinkedIn", categorie: .beroep,
            urlTemplate: "https://www.linkedin.com/search/results/people/?keywords={naam}",
            uitleg: "Je werkhistorie is de rijkste bron over je: werkgevers, jaartallen, regio. Databrokers kopen dit niet, ze schrapen het.",
            verwijderRoute: "Per gegeven kun je je profiel aanpassen; voor een volledig profiel geldt: verwijderen = account opzeggen."),
        ExposureSource(
            id: "github", naam: "GitHub", categorie: .beroep,
            urlTemplate: "https://github.com/search?q={naam}&type=users",
            uitleg: "Je gebruikersnaam koppelt je echte naam aan code, commits en e-mailadressen in oude commits.",
            verwijderRoute: "Naam en e-mail in commits zijn historie: die verwijder je alleen met een herschreven geschiedenis."),
        ExposureSource(
            id: "facebook", naam: "Facebook", categorie: .sociaal,
            urlTemplate: "https://www.facebook.com/search/people/?q={naam}",
            uitleg: "Openbare profielfoto's en vindbaarheid via zoekmachines zijn de bekende lekken; de rest zit achter een login.",
            verwijderRoute: "Zet 'vindbaarheid via zoekmachines' uit en verwijder openbare gegevens per veld."),
        ExposureSource(
            id: "instagram", naam: "Instagram", categorie: .sociaal,
            urlTemplate: "https://www.instagram.com/web/search/topsearch/?query={naam}",
            uitleg: "Een openbaar account is zonder login leesbaar en wordt door derden geïndexeerd.",
            verwijderRoute: "Account op privé zetten of verwijderen; oude tags laten verwijderen."),
        ExposureSource(
            id: "x", naam: "X", categorie: .sociaal,
            urlTemplate: "https://x.com/search?q={naam}&f=user",
            uitleg: "Oude berichten blijven vindbaar, ook als je ze zelf allang niet meer leest.",
            verwijderRoute: "Per bericht verwijderen, of het account opzeggen."),
        ExposureSource(
            id: "wieowie", naam: "Wieowie", categorie: .databroker,
            urlTemplate: "https://www.wieowie.nl/zoek?q={naam}",
            uitleg: "Verzamelpagina die je naam bij 28 andere diensten opzoekt — een handig startpunt, maar geen eigen database: wat je ziet, komt van de bronnen eronder.",
            verwijderRoute: "Verwijderverzoek per e-mail; je hebt recht op verwijdering (AVG artikel 17)."),
        ExposureSource(
            id: "telefoonboek", naam: "Telefoonboek.nl", categorie: .databroker,
            urlTemplate: "https://www.telefoonboek.nl/?q={naam}+{plaats}",
            uitleg: "Telefoongidsen nemen gegevens over uit andere gidsen — één verwijdering haalt zelden alle kopieën weg.",
            verwijderRoute: "Verwijderverzoek per e-mail; noem ook de bron waar de gids de gegevens vandaan heeft."),
    ]

    public static func bron(id: String) -> ExposureSource? {
        bronnen.first { $0.id == id }
    }

    public static func bronnen(in categorie: ExposureCategory) -> [ExposureSource] {
        bronnen.filter { $0.categorie == categorie }
    }
}

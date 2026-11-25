import Foundation

public enum RequestSoort: String, Codable, CaseIterable, Sendable {
    case verwijdering
    case inzage
    case bezwaar

    public var artikel: String {
        switch self {
        case .verwijdering: return "17"
        case .inzage: return "15"
        case .bezwaar: return "21"
        }
    }

    public var titel: String {
        switch self {
        case .verwijdering: return "Verzoek tot verwijdering"
        case .inzage: return "Verzoek tot inzage"
        case .bezwaar: return "Bezwaar tegen verwerking"
        }
    }
}

/// Een kant-en-klare brief op grond van de AVG. Geen verzending: de app maakt
/// de tekst, jij verstuurt hem en houdt de termijn bij.
public struct RemovalRequest: Sendable {
    public let soort: RequestSoort
    public let ontvanger: String
    public let naam: String
    public let gegevens: String
    public let verstuurdOp: Date

    public init(soort: RequestSoort, ontvanger: String, naam: String,
                gegevens: String, verstuurdOp: Date = Date()) {
        self.soort = soort
        self.ontvanger = ontvanger
        self.naam = naam
        self.gegevens = gegevens
        self.verstuurdOp = verstuurdOp
    }

    /// Artikel 12 lid 3 AVG: één maand na ontvangst. kalenderrekening, dus
    /// 31 januari wordt 28 (of 29) februari.
    public var deadline: Date {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        return kalender.date(byAdding: .month, value: 1, to: verstuurdOp) ?? verstuurdOp
    }

    public func tekst() -> String {
        let kern: String
        switch soort {
        case .verwijdering:
            kern = """
            Ik verzoek u op grond van artikel 17 van de Algemene verordening gegevensbescherming (AVG) \
            om de volgende persoonsgegevens over mij te verwijderen:

                \(gegevens)

            Het gaat om gegevens die herleidbaar zijn tot mijn naam: \(naam). Ik verzoek u daarbij ook \
            om deze gegevens niet opnieuw te publiceren of te verstrekken aan derden.
            """
        case .inzage:
            kern = """
            Ik verzoek u op grond van artikel 15 van de Algemene verordening gegevensbescherming (AVG) \
            om mij een kopie te sturen van alle persoonsgegevens die u over mij verwerkt, en om mij te \
            laten weten:

                - welke gegevens het zijn en waar ze vandaan komen;
                - aan wie ze zijn verstrekt;
                - hoe lang u ze bewaart;
                - op welke grondslag u ze verwerkt.

            Het gaat in elk geval om: \(gegevens), herleidbaar tot mijn naam: \(naam).
            """
        case .bezwaar:
            kern = """
            Ik maak op grond van artikel 21 van de Algemene verordening gegevensbescherming (AVG) \
            bezwaar tegen de verwerking van mijn persoonsgegevens voor de volgende doeleinden:

                \(gegevens)

            Het gaat om gegevens herleidbaar tot mijn naam: \(naam). Ik verzoek u de verwerking te \
            staken en mij te laten weten welke gegevens u daarna nog bewaart, en op welke grondslag.
            """
        }

        return """
        \(naam)

        \(ontvanger)

        Betreft: \(soort.titel) — \(naam)

        Geachte heer, mevrouw,

        \(kern)

        Op grond van artikel 12, lid 3, van de Algemene verordening gegevensbescherming verwacht ik uw \
        reactie binnen één maand na ontvangst van dit bericht. Reageert u niet of niet volledig, dan \
        leg ik de zaak voor aan de Autoriteit Persoonsgegevens.

        Wilt u in uw antwoord aangeven welke gegevens u heeft verwijderd of aangepast, en welke u \
        meent te moeten bewaren — met de grondslag daarvoor?

        Met vriendelijke groet,

        \(naam)
        """
    }
}

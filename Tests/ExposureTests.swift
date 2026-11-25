import XCTest
@testable import Crumb

/// Nulmeting van het eigen spoor: welke bronnen, welke links, welke brieven.
/// Alles lokaal en Foundation-only — geen netwerk, geen scraping.
final class ExposureSourceTests: XCTestCase {

    func testElkeBronHeeftHTTPSEnEenNaamplaats() {
        XCTAssertFalse(ExposureCatalog.bronnen.isEmpty)
        for bron in ExposureCatalog.bronnen {
            XCTAssertTrue(bron.urlTemplate.hasPrefix("https://"), "\(bron.id) is niet https")
            XCTAssertTrue(bron.urlTemplate.contains("{naam}"), "\(bron.id) mist {naam}")
            XCTAssertFalse(bron.naam.isEmpty)
            XCTAssertFalse(bron.uitleg.isEmpty)
        }
    }

    func testBouwURLCodeertNaamEnPlaats() throws {
        let google = try XCTUnwrap(ExposureCatalog.bron(id: "google"))
        let url = try XCTUnwrap(google.url(naam: "Tiëndo Welles", plaats: "Waddinxveen"))
        let tekst = url.absoluteString
        XCTAssertTrue(tekst.contains("Ti%C3%ABndo%20Welles"), "naam niet correct gecodeerd: \(tekst)")
        XCTAssertTrue(tekst.contains("Waddinxveen"))
        XCTAssertFalse(tekst.contains("Ã"), "dubbele codering: \(tekst)")
        XCTAssertFalse(tekst.contains(" "), "spatie niet gecodeerd: \(tekst)")
    }

    func testBouwURLZonderPlaatsLaatGeenPlaatshouderStaan() throws {
        let linkedin = try XCTUnwrap(ExposureCatalog.bron(id: "linkedin"))
        let url = try XCTUnwrap(linkedin.url(naam: "Tiëndo Welles", plaats: nil))
        XCTAssertFalse(url.absoluteString.contains("{plaats}"))
        XCTAssertTrue(url.absoluteString.contains("Ti%C3%ABndo"))
    }

    func testLegeNaamGeeftGeenURL() {
        let google = ExposureCatalog.bron(id: "google")!
        XCTAssertNil(google.url(naam: "   ", plaats: nil))
    }

    func testCatalogusBevatNederlandseDatabronnen() {
        let ids = Set(ExposureCatalog.bronnen.map(\.id))
        for verplicht in ["google", "bing", "duckduckgo", "linkedin", "github",
                          "facebook", "instagram", "x", "wieowie", "telefoonboek"] {
            XCTAssertTrue(ids.contains(verplicht), "bron \(verplicht) ontbreekt")
        }
    }

    func testElkeBronHeeftEenVerwijderRoute() {
        for bron in ExposureCatalog.bronnen {
            XCTAssertFalse(bron.verwijderRoute.isEmpty, "\(bron.id) heeft geen verwijderroute")
        }
    }
}

final class RemovalRequestTests: XCTestCase {

    private func datum(_ tekst: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: tekst)!
    }

    func testVerwijderverzoekBevatArtikel17NaamEnOntvanger() {
        let brief = RemovalRequest(soort: .verwijdering, ontvanger: "Wieowie B.V.",
                                   naam: "Tiëndo Welles", gegevens: "naam en woonplaats",
                                   verstuurdOp: datum("2026-11-25"))
        let tekst = brief.tekst()
        XCTAssertTrue(tekst.contains("artikel 17"))
        XCTAssertTrue(tekst.contains("Tiëndo Welles"))
        XCTAssertTrue(tekst.contains("Wieowie B.V."))
        XCTAssertTrue(tekst.contains("naam en woonplaats"))
    }

    func testInzageverzoekBevatArtikel15() {
        let brief = RemovalRequest(soort: .inzage, ontvanger: "Google Ireland Limited",
                                   naam: "Tiëndo Welles", gegevens: "zoekresultaten",
                                   verstuurdOp: datum("2026-11-25"))
        XCTAssertTrue(brief.tekst().contains("artikel 15"))
    }

    func testBezwaarBevatArtikel21() {
        let brief = RemovalRequest(soort: .bezwaar, ontvanger: "Meta Platforms Ireland",
                                   naam: "Tiëndo Welles", gegevens: "advertentieprofiel",
                                   verstuurdOp: datum("2026-11-25"))
        XCTAssertTrue(brief.tekst().contains("artikel 21"))
    }

    func testBriefNoemtDeTermijnVanEenMaand() {
        let brief = RemovalRequest(soort: .verwijdering, ontvanger: "X",
                                   naam: "T", gegevens: "gegevens", verstuurdOp: datum("2026-11-25"))
        XCTAssertTrue(brief.tekst().contains("één maand"))
        XCTAssertTrue(brief.tekst().contains("artikel 12"))
    }

    func testDeadlineIsEenMaandLater() {
        let brief = RemovalRequest(soort: .verwijdering, ontvanger: "X", naam: "T",
                                   gegevens: "g", verstuurdOp: datum("2026-01-31"))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        XCTAssertEqual(f.string(from: brief.deadline), "2026-02-28")
    }

    func testDeadlineInSchrikkeljaar() {
        let brief = RemovalRequest(soort: .verwijdering, ontvanger: "X", naam: "T",
                                   gegevens: "g", verstuurdOp: datum("2028-01-31"))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        XCTAssertEqual(f.string(from: brief.deadline), "2028-02-29")
    }

    func testBriefIsOpgesteldInHetNederlands() {
        let brief = RemovalRequest(soort: .verwijdering, ontvanger: "Wieowie B.V.",
                                   naam: "Tiëndo Welles", gegevens: "naam en woonplaats",
                                   verstuurdOp: datum("2026-11-25"))
        let tekst = brief.tekst()
        XCTAssertTrue(tekst.contains("Geachte"))
        XCTAssertTrue(tekst.contains("Algemene verordening gegevensbescherming"))
        XCTAssertTrue(tekst.contains("Met vriendelijke groet"))
    }
}

final class ExposureLedgerTests: XCTestCase {

    private var map: URL!

    override func setUpWithError() throws {
        map = FileManager.default.temporaryDirectory
            .appendingPathComponent("crumb-sporen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: map)
    }

    private func voorbeeld() -> ExposureEntry {
        ExposureEntry(sourceID: "wieowie", sourceNaam: "Wieowie",
                      url: "https://www.wieowie.nl/?q=Ti%C3%ABndo",
                      gevondenOp: Date(timeIntervalSince1970: 1_764_000_000),
                      deadline: Date(timeIntervalSince1970: 1_766_000_000),
                      notitie: "naam en woonplaats")
    }

    func testToevoegenEnTeruglezen() {
        let boek = ExposureLedger(bestand: nil)
        let id = boek.voegToe(voorbeeld())!
        XCTAssertEqual(boek.entries.count, 1)
        XCTAssertEqual(boek.entry(id: id)?.sourceID, "wieowie")
        XCTAssertEqual(boek.entry(id: id)?.status, .gevonden)
    }

    func testOpslaanEnLaden() throws {
        let bestand = map.appendingPathComponent("sporen.json")
        let boek = ExposureLedger(bestand: bestand)
        let id = boek.voegToe(voorbeeld())!
        boek.zetStatus(id: id, .verzoekVerstuurd)
        try boek.bewaar()

        let terug = ExposureLedger(bestand: bestand)
        try terug.laad()
        XCTAssertEqual(terug.entries.count, 1)
        XCTAssertEqual(terug.entry(id: id)?.status, .verzoekVerstuurd)
    }

    func testOpenstaandTeltAlleenNietAfgehandeldeSporen() {
        let boek = ExposureLedger(bestand: nil)
        let a = boek.voegToe(voorbeeld())!
        let b = boek.voegToe(voorbeeld())!
        boek.zetStatus(id: b, .verwijderd)
        XCTAssertEqual(boek.openstaand().map(\.id), [a])
    }

    func testOverTijdNaDeadline() {
        let boek = ExposureLedger(bestand: nil)
        let teLaat = ExposureEntry(sourceID: "x", sourceNaam: "X", url: "https://x.nl",
                                  gevondenOp: Date(timeIntervalSince1970: 1_700_000_000),
                                  deadline: Date(timeIntervalSince1970: 1_700_086_400),
                                  notitie: "")
        _ = boek.voegToe(teLaat)
        XCTAssertTrue(boek.overTijd(nu: Date(timeIntervalSince1970: 1_700_200_000)).count == 1)
        XCTAssertTrue(boek.overTijd(nu: Date(timeIntervalSince1970: 1_699_000_000)).isEmpty)
    }

    func testVerwijderdeSporenZijnNooitOverTijd() {
        let boek = ExposureLedger(bestand: nil)
        let id = boek.voegToe(voorbeeld())!
        boek.zetStatus(id: id, .verwijderd)
        XCTAssertTrue(boek.overTijd(nu: Date(timeIntervalSince1970: 1_900_000_000)).isEmpty)
    }

    func testOnbekendeBronWordtGeweigerd() {
        let boek = ExposureLedger(bestand: nil)
        let nep = ExposureEntry(sourceID: "bestaatniet", sourceNaam: "?",
                                url: "", gevondenOp: Date(), deadline: Date(), notitie: "")
        XCTAssertNil(boek.voegToe(nep))
    }
}

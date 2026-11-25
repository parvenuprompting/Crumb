import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Crumb

/// Kleine doos om het verzoek uit de zender te halen zonder een var te vangen.
private final class Verzoekdoos: @unchecked Sendable {
    var verzoek: URLRequest?
}

final class ExposureSyncClientTests: XCTestCase {

    private func antwoord(_ code: Int, _ lichaam: String) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://huis:7467/api/sporen/sync")!,
                        statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    private func record() -> SpoorRecord {
        SpoorRecord(id: UUID().uuidString, bron: "google", naam: "Google",
                    url: "https://www.google.com/search?q=x", notitie: "gevonden",
                    gevonden: "2026-11-24", termijn: "2026-12-24",
                    status: "gevonden", gewijzigd: 1_764_000_000)
    }

    func testEindpuntMetEnZonderSlash() {
        XCTAssertEqual(ExposureSyncClient(adres: "https://huis:7467", sleutel: "k").eindpunt?.absoluteString,
                       "https://huis:7467/api/sporen/sync")
        XCTAssertEqual(ExposureSyncClient(adres: "https://huis:7467/", sleutel: "k").eindpunt?.absoluteString,
                       "https://huis:7467/api/sporen/sync")
    }

    func testEindpuntBestaandPadBlijftStaan() {
        let client = ExposureSyncClient(adres: "https://huis:7467/api/sporen/sync", sleutel: "k")
        XCTAssertEqual(client.eindpunt?.absoluteString, "https://huis:7467/api/sporen/sync")
    }

    func testLeegAdresGeeftNil() {
        XCTAssertNil(ExposureSyncClient(adres: "   ", sleutel: "k").eindpunt)
    }

    func testLeegAdresWerptFout() async {
        let client = ExposureSyncClient(adres: "", sleutel: "k") { _ in
            XCTFail("mag niet zenden")
            throw SyncFout.geenAdres
        }
        do { _ = try await client.synchroniseer([]); XCTFail("had moeten werpen") }
        catch let fout as SyncFout { XCTAssertEqual(fout, .geenAdres) }
        catch { XCTFail("verkeerde fout: \(error)") }
    }

    func testVerzoekHeeftMethodeKopEnRecords() async throws {
        let doos = Verzoekdoos()
        let client = ExposureSyncClient(adres: "https://huis:7467", sleutel: "geheim") { verzoek in
            doos.verzoek = verzoek
            return (Data(#"{"records":[]}"#.utf8), self.antwoord(200, "{}"))
        }
        _ = try await client.synchroniseer([record()])

        let verzoek = try XCTUnwrap(doos.verzoek)
        XCTAssertEqual(verzoek.httpMethod, "POST")
        XCTAssertEqual(verzoek.value(forHTTPHeaderField: "X-Joker-Token"), "geheim")
        XCTAssertEqual(verzoek.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(verzoek.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let records = try XCTUnwrap(json?["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["bron"] as? String, "google")
    }

    func testAntwoordWordtTeruggegeven() async throws {
        let client = ExposureSyncClient(adres: "https://huis:7467", sleutel: "k") { _ in
            (Data(#"{"records":[{"id":"a","bron":"bing","status":"verzoekVerstuurd","gewijzigd":5}]}"#.utf8),
             self.antwoord(200, "{}"))
        }
        let uit = try await client.synchroniseer([])
        XCTAssertEqual(uit.count, 1)
        XCTAssertEqual(uit[0].status, "verzoekVerstuurd")
        XCTAssertEqual(uit[0].gewijzigd, 5)
    }

    func test403GeeftSleutelAfgewezen() async {
        let client = ExposureSyncClient(adres: "https://huis:7467", sleutel: "fout") { _ in
            (Data(), self.antwoord(403, ""))
        }
        do { _ = try await client.synchroniseer([]); XCTFail("had moeten werpen") }
        catch let fout as SyncFout { XCTAssertEqual(fout, .sleutelAfgewezen) }
        catch { XCTFail("verkeerde fout: \(error)") }
    }

    func testServerfoutNeemtDeTekstMee() async {
        let client = ExposureSyncClient(adres: "https://huis:7467", sleutel: "k") { _ in
            (Data(#"{"fout":"records ontbreekt"}"#.utf8), self.antwoord(400, ""))
        }
        do { _ = try await client.synchroniseer([]); XCTFail("had moeten werpen") }
        catch let fout as SyncFout { XCTAssertEqual(fout, .server("records ontbreekt")) }
        catch { XCTFail("verkeerde fout: \(error)") }
    }

    func testOnleesbaarAntwoord() async {
        let client = ExposureSyncClient(adres: "https://huis:7467", sleutel: "k") { _ in
            (Data("<html>geen json</html>".utf8), self.antwoord(200, "{}"))
        }
        do { _ = try await client.synchroniseer([]); XCTFail("had moeten werpen") }
        catch let fout as SyncFout { XCTAssertEqual(fout, .antwoordOnleesbaar) }
        catch { XCTFail("verkeerde fout: \(error)") }
    }
}

final class SpoorVertalingTests: XCTestCase {

    private func datum(_ tekst: String) -> Date {
        SpoorVertaling.dag.date(from: tekst)!
    }

    func testHeenEnWeerBehoudtAllesWatTelt() throws {
        let entry = ExposureEntry(sourceID: "linkedin", sourceNaam: "LinkedIn",
                                  url: "https://www.linkedin.com/in/x",
                                  gevondenOp: datum("2026-11-20"),
                                  deadline: datum("2026-12-20"),
                                  status: .verzoekVerstuurd,
                                  notitie: "profiel",
                                  gewijzigd: Date(timeIntervalSince1970: 1_764_000_000))
        let terug = try XCTUnwrap(SpoorVertaling.entry(van: SpoorVertaling.record(van: entry)))
        XCTAssertEqual(terug.id, entry.id)
        XCTAssertEqual(terug.sourceID, "linkedin")
        XCTAssertEqual(terug.status, .verzoekVerstuurd)
        XCTAssertEqual(terug.url, entry.url)
        XCTAssertEqual(terug.notitie, "profiel")
        XCTAssertEqual(SpoorVertaling.dag.string(from: terug.deadline), "2026-12-20")
        XCTAssertEqual(terug.laatstGewijzigd.timeIntervalSince1970, 1_764_000_000, accuracy: 1)
    }

    func testRecordZonderBekendeBronWordtGeweigerd() {
        let r = SpoorRecord(id: UUID().uuidString, bron: "bestaatniet", status: "gevonden", gewijzigd: 0)
        XCTAssertNil(SpoorVertaling.entry(van: r))
    }

    func testRecordMetOnbruikbareIdWordtGeweigerd() {
        let r = SpoorRecord(id: "geen-uuid", bron: "google", status: "gevonden", gewijzigd: 0)
        XCTAssertNil(SpoorVertaling.entry(van: r))
    }

    func testOnbekendeStatusWordtGevonden() {
        let r = SpoorRecord(id: UUID().uuidString, bron: "google", status: "verzonnen", gewijzigd: 0)
        XCTAssertEqual(SpoorVertaling.entry(van: r)?.status, .gevonden)
    }
}

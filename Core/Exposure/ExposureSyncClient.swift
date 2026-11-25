import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Eén spoor op de lijn. Bewust plat en zonder Date-objecten: het huis rekent
/// met dagen (yyyy-MM-dd) en met epoch-seconden voor "wie was er het laatst".
public struct SpoorRecord: Codable, Equatable, Sendable {
    public var id: String
    public var bron: String
    public var naam: String?
    public var url: String?
    public var notitie: String?
    public var gevonden: String?
    public var termijn: String?
    public var status: String
    public var gewijzigd: Double

    public init(id: String, bron: String, naam: String? = nil, url: String? = nil,
                notitie: String? = nil, gevonden: String? = nil, termijn: String? = nil,
                status: String, gewijzigd: Double) {
        self.id = id
        self.bron = bron
        self.naam = naam
        self.url = url
        self.notitie = notitie
        self.gevonden = gevonden
        self.termijn = termijn
        self.status = status
        self.gewijzigd = gewijzigd
    }
}

public enum SyncFout: LocalizedError, Equatable {
    case geenAdres
    case sleutelAfgewezen
    case server(String)
    case antwoordOnleesbaar

    public var errorDescription: String? {
        switch self {
        case .geenAdres: return "Vul eerst het adres van je huis in."
        case .sleutelAfgewezen: return "De sleutel werd niet geaccepteerd. Kopieer hem opnieuw uit het huis."
        case .server(let tekst): return "Het huis antwoordde: \(tekst)"
        case .antwoordOnleesbaar: return "Het antwoord van het huis was niet te lezen."
        }
    }
}

/// Praat met `POST /api/sporen/sync` in het Joker-huis.
///
/// De client voegt niets zelf samen: het huis is de enige die dat doet, zodat
/// Mac en telefoon nooit met twee verschillende regels werken. De app stuurt
/// wat hij heeft, krijgt de samengevoegde lijst terug en schrijft die op.
public struct ExposureSyncClient: Sendable {

    public typealias Zender = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public let adres: String
    public let sleutel: String
    private let zender: Zender

    public init(adres: String, sleutel: String,
                zender: @escaping Zender = ExposureSyncClient.standaardZender) {
        self.adres = adres
        self.sleutel = sleutel
        self.zender = zender
    }

    /// Het eindpunt. Een adres met of zonder slash, met of zonder pad: het komt goed.
    public var eindpunt: URL? {
        let schoon = adres.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !schoon.isEmpty else { return nil }
        var tekst = schoon
        if tekst.hasSuffix("/") { tekst.removeLast() }
        if !tekst.lowercased().hasSuffix("/api/sporen/sync") {
            tekst += "/api/sporen/sync"
        }
        return URL(string: tekst)
    }

    public func synchroniseer(_ records: [SpoorRecord]) async throws -> [SpoorRecord] {
        guard let eindpunt else { throw SyncFout.geenAdres }
        var verzoek = URLRequest(url: eindpunt)
        verzoek.httpMethod = "POST"
        verzoek.timeoutInterval = 30
        verzoek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        verzoek.setValue(sleutel, forHTTPHeaderField: "X-Joker-Token")
        verzoek.httpBody = try JSONEncoder().encode(["records": records])

        let (data, antwoord) = try await zender(verzoek)

        if antwoord.statusCode == 403 { throw SyncFout.sleutelAfgewezen }
        guard antwoord.statusCode == 200 else {
            let melding = (try? JSONDecoder().decode(FoutAntwoord.self, from: data))?.fout
            throw SyncFout.server(melding ?? "http \(antwoord.statusCode)")
        }
        guard let uit = try? JSONDecoder().decode(SyncAntwoord.self, from: data) else {
            throw SyncFout.antwoordOnleesbaar
        }
        return uit.records
    }

    public static let standaardZender: Zender = { verzoek in
        try await withCheckedThrowingContinuation { vervolg in
            URLSession.shared.dataTask(with: verzoek) { data, antwoord, fout in
                if let fout {
                    return vervolg.resume(throwing: fout)
                }
                guard let data, let http = antwoord as? HTTPURLResponse else {
                    return vervolg.resume(throwing: SyncFout.antwoordOnleesbaar)
                }
                vervolg.resume(returning: (data, http))
            }.resume()
        }
    }

    private struct SyncAntwoord: Decodable { let records: [SpoorRecord] }
    private struct FoutAntwoord: Decodable { let fout: String }
}

// MARK: - heen en weer tussen de app en de lijn

public enum SpoorVertaling {

    static let dag: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func record(van entry: ExposureEntry) -> SpoorRecord {
        SpoorRecord(id: entry.id.uuidString,
                    bron: entry.sourceID,
                    naam: entry.sourceNaam,
                    url: entry.url,
                    notitie: entry.notitie,
                    gevonden: dag.string(from: entry.gevondenOp),
                    termijn: dag.string(from: entry.deadline),
                    status: entry.status.rawValue,
                    gewijzigd: entry.laatstGewijzigd.timeIntervalSince1970)
    }

    /// Nil als het record geen bruikbare bron of datum heeft: liever niets dan een
    /// spoor dat je niet kunt natrekken.
    public static func entry(van record: SpoorRecord) -> ExposureEntry? {
        guard ExposureCatalog.bron(id: record.bron) != nil else { return nil }
        guard let id = UUID(uuidString: record.id) else { return nil }
        let gevonden = dag.date(from: record.gevonden ?? "") ?? Date()
        let termijn = dag.date(from: record.termijn ?? "") ?? gevonden
        return ExposureEntry(id: id,
                             sourceID: record.bron,
                             sourceNaam: record.naam ?? (ExposureCatalog.bron(id: record.bron)?.naam ?? record.bron),
                             url: record.url ?? "",
                             gevondenOp: gevonden,
                             deadline: termijn,
                             status: ExposureStatus(rawValue: record.status) ?? .gevonden,
                             notitie: record.notitie ?? "",
                             gewijzigd: Date(timeIntervalSince1970: record.gewijzigd))
    }
}

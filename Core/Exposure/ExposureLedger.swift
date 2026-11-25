import Foundation

public enum ExposureStatus: String, Codable, CaseIterable, Sendable {
    case gevonden
    case verzoekVerstuurd
    case verwijderd
    case geenAntwoord

    public var titel: String {
        switch self {
        case .gevonden: return "Gevonden"
        case .verzoekVerstuurd: return "Verzoek verstuurd"
        case .verwijderd: return "Verwijderd"
        case .geenAntwoord: return "Geen antwoord"
        }
    }

    var isAfgehandeld: Bool { self == .verwijderd }
}

public struct ExposureEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceID: String
    public let sourceNaam: String
    public let url: String
    public let gevondenOp: Date
    public let deadline: Date
    public var status: ExposureStatus
    public var notitie: String

    public init(id: UUID = UUID(), sourceID: String, sourceNaam: String, url: String,
                gevondenOp: Date = Date(), deadline: Date, status: ExposureStatus = .gevonden,
                notitie: String = "") {
        self.id = id
        self.sourceID = sourceID
        self.sourceNaam = sourceNaam
        self.url = url
        self.gevondenOp = gevondenOp
        self.deadline = deadline
        self.status = status
        self.notitie = notitie
    }
}

/// De administratie van je eigen spoor: wat je vond, wat je verstuurde, wat
/// binnen de termijn valt. Lokaal, in een JSON-bestand, zonder netwerk.
public final class ExposureLedger {

    public private(set) var entries: [ExposureEntry] = []
    private let bestand: URL?

    /// `bestand == nil` houdt alles in het geheugen (gebruikt door de tests).
    public init(bestand: URL?) {
        self.bestand = bestand
    }

    /// Geeft nil als de bron niet in de catalogus bestaat — een spoor zonder
    /// echte bron is een spoor dat je niet kunt natrekken.
    @discardableResult
    public func voegToe(_ entry: ExposureEntry) -> UUID? {
        guard ExposureCatalog.bron(id: entry.sourceID) != nil else { return nil }
        entries.append(entry)
        return entry.id
    }

    public func entry(id: UUID) -> ExposureEntry? {
        entries.first { $0.id == id }
    }

    public func zetStatus(id: UUID, _ status: ExposureStatus) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].status = status
    }

    public func openstaand() -> [ExposureEntry] {
        entries.filter { !$0.status.isAfgehandeld }
    }

    /// Sporen waarvan de wettelijke termijn (art. 12 lid 3) voorbij is.
    public func overTijd(nu: Date = Date()) -> [ExposureEntry] {
        entries.filter { !$0.status.isAfgehandeld && $0.deadline < nu }
    }

    public func bewaar() throws {
        guard let bestand else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try FileManager.default.createDirectory(at: bestand.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: bestand, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bestand.path)
    }

    public func laad() throws {
        guard let bestand, FileManager.default.fileExists(atPath: bestand.path) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = try decoder.decode([ExposureEntry].self, from: Data(contentsOf: bestand))
    }

    /// Standaardplek: Application Support/Crumb/sporen.json
    public static func standaardBestand() -> URL? {
        guard let map = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first else { return nil }
        return map.appendingPathComponent("Crumb", isDirectory: true)
                  .appendingPathComponent("sporen.json")
    }
}

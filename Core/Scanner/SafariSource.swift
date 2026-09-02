import Foundation

struct ParsedBinaryCookie: Sendable, Equatable {
    var domain: String
    var name: String
    var path: String
    var isSecure: Bool
    var isHttpOnly: Bool
    var expiry: Date?
    var creation: Date?
}

/// Parser voor Safari's `Cookies.binarycookies`. Canonieke formaatbeschrijving:
///
///   Bestand: "cook" | u32 LE paginatelling | per pagina u32 LE paginagrootte | pagina's sequentieel
///   Pagina:  u32 LE header (0x00000100) | u32 LE cookie-telling | offsets LE t.o.v. paginastart | entries
///   Cookie:  u32 LE grootte | u32 LE vlaggen | u32 BE url-offset | u32 BE naam-offset |
///            u32 BE pad-offset | u32 BE waarde-offset (bewust ongebruikt) |
///            f64 LE vervaldatum | f64 LE aanmaakdatum | u32 onbekend
///
/// Beschadigde pagina's of cookies worden overgeslagen — één corrupte pagina
/// mag de hele Safari-scan niet platleggen.
enum BinaryCookiesParser {
    private static let referenceDate = Date(timeIntervalSince1970: 978_307_200)
    private static let maxPages = 10_000
    private static let maxCookiesPerPage = 100_000
    private static let cookieHeaderSize = 44

    static func parse(data: Data) throws -> [ParsedBinaryCookie] {
        guard data.count >= 8, data.prefix(4) == Data("cook".utf8) else {
            throw CookieScanError.readFailed("Ongeldig binarycookies-formaat (magic ontbreekt).")
        }

        let pageCount = Int(readUInt32LE(data, offset: 4))
        guard pageCount > 0, pageCount <= maxPages, data.count >= 8 + pageCount * 4 else {
            return []
        }

        // De paginatabel bevat paginagroottes; pagina's volgen direct op elkaar.
        var pageSizes: [Int] = []
        for index in 0..<pageCount {
            pageSizes.append(Int(readUInt32LE(data, offset: 8 + index * 4)))
        }

        var cookies: [ParsedBinaryCookie] = []
        var pageStart = 8 + pageCount * 4
        for size in pageSizes {
            cookies.append(contentsOf: parsePage(data: data, pageStart: pageStart, pageSize: size))
            pageStart += size
        }
        return cookies
    }

    private static func parsePage(data: Data, pageStart: Int, pageSize: Int) -> [ParsedBinaryCookie] {
        guard pageSize >= 8, pageStart >= 0, data.count >= pageStart + 8 else { return [] }
        let pageEnd = min(pageStart + pageSize, data.count)

        let cookieCount = Int(readUInt32LE(data, offset: pageStart + 4))
        guard cookieCount > 0, cookieCount <= maxCookiesPerPage,
              pageEnd >= pageStart + 8 + cookieCount * 4 else {
            return []
        }

        var cookies: [ParsedBinaryCookie] = []
        for index in 0..<cookieCount {
            let relativeOffset = Int(readUInt32LE(data, offset: pageStart + 8 + index * 4))
            let cookieStart = pageStart + relativeOffset
            guard cookieStart >= pageStart, cookieStart < pageEnd else { continue }
            if let cookie = parseCookie(data: data, entryStart: cookieStart, entryEnd: pageEnd) {
                cookies.append(cookie)
            }
        }
        return cookies
    }

    private static func parseCookie(data: Data, entryStart: Int, entryEnd: Int) -> ParsedBinaryCookie? {
        guard entryEnd - entryStart >= cookieHeaderSize else { return nil }

        let entrySize = Int(readUInt32LE(data, offset: entryStart))
        let flags = readUInt32LE(data, offset: entryStart + 4)
        // URL-, naam- en pad-offsets zijn big-endian in het Safari-formaat.
        let urlOffset = Int(readUInt32BE(data, offset: entryStart + 8))
        let nameOffset = Int(readUInt32BE(data, offset: entryStart + 12))
        let pathOffset = Int(readUInt32BE(data, offset: entryStart + 16))
        // Waarde-offset (+20) wordt bewust genegeerd: cookie-waarden blijven onaangeroerd.
        let expiry = readDoubleLE(data, offset: entryStart + 24)
        let creation = readDoubleLE(data, offset: entryStart + 32)

        let limit = entrySize > 0 ? min(entryStart + entrySize, entryEnd) : entryEnd
        guard let url = readNullTerminatedString(data: data, offset: entryStart + urlOffset, limit: limit),
              let name = readNullTerminatedString(data: data, offset: entryStart + nameOffset, limit: limit),
              let path = readNullTerminatedString(data: data, offset: entryStart + pathOffset, limit: limit) else {
            return nil
        }

        let isSessionOnly = expiry == 0
        return ParsedBinaryCookie(
            domain: normalizedDomain(url),
            name: name,
            path: path,
            isSecure: flags & 0x1 != 0,
            isHttpOnly: flags & 0x4 != 0,
            expiry: isSessionOnly ? nil : referenceDate.addingTimeInterval(expiry),
            creation: referenceDate.addingTimeInterval(creation)
        )
    }

    private static func normalizedDomain(_ url: String) -> String {
        url.hasPrefix(".") ? String(url.dropFirst()) : url
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: (data.startIndex + offset)..<(data.startIndex + offset + 4))
        }
        return value.littleEndian
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: (data.startIndex + offset)..<(data.startIndex + offset + 4))
        }
        return value.bigEndian
    }

    private static func readDoubleLE(_ data: Data, offset: Int) -> Double {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        var bits: UInt64 = 0
        withUnsafeMutableBytes(of: &bits) { dest in
            data.copyBytes(to: dest, from: (data.startIndex + offset)..<(data.startIndex + offset + 8))
        }
        return Double(bitPattern: bits.littleEndian)
    }

    private static func readNullTerminatedString(data: Data, offset: Int, limit: Int) -> String? {
        guard offset >= 0, limit <= data.count, offset < limit else { return nil }
        var end = offset
        while end < limit, data[data.startIndex + end] != 0 { end += 1 }
        guard end > offset else { return nil }
        return String(data: data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end)), encoding: .utf8)
    }
}

struct SafariSource: CookieSource {
    let browserName = "Safari"
    private let fileManager = FileManager.default

    var cookieFileURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
    }

    var isInstalled: Bool { true }

    var isAccessible: Bool {
        (try? Data(contentsOf: cookieFileURL)) != nil
    }

    func scan() throws -> [RawCookie] {
        let data: Data
        do {
            data = try Data(contentsOf: cookieFileURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain {
            if error.code == NSFileReadNoPermissionError {
                throw CookieScanError.fullDiskAccessRequired(path: cookieFileURL.path)
            }
            throw CookieScanError.readFailed(error.localizedDescription)
        }

        return try BinaryCookiesParser.parse(data: data).map { parsed in
            RawCookie(
                domain: parsed.domain,
                name: parsed.name,
                path: parsed.path,
                expiry: parsed.expiry,
                creation: parsed.creation,
                isSecure: parsed.isSecure,
                isHttpOnly: parsed.isHttpOnly,
                isSessionOnly: parsed.expiry == nil
            )
        }
    }
}

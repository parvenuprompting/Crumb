import Foundation

struct ParsedBinaryCookie: Sendable {
    var domain: String
    var name: String
    var path: String
    var isSecure: Bool
    var isHttpOnly: Bool
    var expiry: Date?
    var creation: Date?
}

enum BinaryCookiesParser {
    private static let referenceDate = Date(timeIntervalSince1970: 978_307_200)

    static func parse(data: Data) throws -> [ParsedBinaryCookie] {
        guard data.count >= 8, data.prefix(4) == Data("cook".utf8) else {
            throw CookieScanError.readFailed("Ongeldig binarycookies-formaat (magic ontbreekt).")
        }

        let pageCount = Self.readUInt32(data, offset: 4)
        var offset = 8
        var pageOffsets: [Int] = []
        for _ in 0..<pageCount {
            pageOffsets.append(offset)
            offset += 4
        }

        var cookies: [ParsedBinaryCookie] = []
        for pageOffset in pageOffsets {
            let pageStart = Self.readUInt32(data, offset: pageOffset)
            cookies.append(contentsOf: try parsePage(data: data, pageStart: Int(pageStart)))
        }
        return cookies
    }

    private static func parsePage(data: Data, pageStart: Int) throws -> [ParsedBinaryCookie] {
        guard data.count >= pageStart + 12 else {
            throw CookieScanError.readFailed("Pagina valt buiten bestand.")
        }
        let cookieCount = Int(readUInt32(data, offset: pageStart + 8))
        var cookieOffsets: [Int] = []
        var offset = pageStart + 12
        for _ in 0..<cookieCount {
            cookieOffsets.append(Int(readUInt32(data, offset: offset)))
            offset += 4
        }

        return cookieOffsets.compactMap { cookieOffset in
            parseCookie(data: data, entryStart: pageStart + cookieOffset)
        }
    }

    private static func parseCookie(data: Data, entryStart: Int) -> ParsedBinaryCookie? {
        guard data.count >= entryStart + 44 else { return nil }

        let flags = readUInt32(data, offset: entryStart + 4)
        let urlOffset = Int(readUInt32(data, offset: entryStart + 12))
        let nameOffset = Int(readUInt32(data, offset: entryStart + 16))
        let pathOffset = Int(readUInt32(data, offset: entryStart + 20))
        let expiry = readDouble(data, offset: entryStart + 28)
        let creation = readDouble(data, offset: entryStart + 36)

        guard let url = readString(data, offset: entryStart + urlOffset),
              let name = readString(data, offset: entryStart + nameOffset),
              let path = readString(data, offset: entryStart + pathOffset) else {
            return nil
        }

        let isSessionOnly = expiry == 0
        return ParsedBinaryCookie(
            domain: Self.normalizedDomain(url),
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

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<offset + 4)
        }
        return value.littleEndian
    }

    private static func readDouble(_ data: Data, offset: Int) -> Double {
        guard offset + 8 <= data.count else { return 0 }
        var bits: UInt64 = 0
        withUnsafeMutableBytes(of: &bits) { dest in
            data.copyBytes(to: dest, from: offset..<offset + 8)
        }
        return Double(bitPattern: bits.littleEndian)
    }

    private static func readString(_ data: Data, offset: Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count, data[data.startIndex + end] != 0 { end += 1 }
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

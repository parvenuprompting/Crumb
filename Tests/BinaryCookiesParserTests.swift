import XCTest
@testable import Crumb

final class BinaryCookiesParserTests: XCTestCase {
    private func uint32LE(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func uint32BE(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private func doubleLE(_ value: Double) -> Data {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) }
    }

    private func string(_ value: String) -> Data {
        Data(value.utf8) + Data([0])
    }

    /// Cookie-entry in het canonieke Safari-formaat: u32 LE grootte, u32 LE
    /// vlaggen, u32 BE offsets voor url/naam/pad/waarde, f64 LE expiry/creation.
    private func makeCookieEntry(
        url: String,
        name: String,
        path: String,
        value: String,
        flags: UInt32,
        expiry: Double,
        creation: Double
    ) -> Data {
        let urlData = string(url)
        let nameData = string(name)
        let pathData = string(path)
        let valueData = string(value)

        let headerSize = 44
        let urlOffset = headerSize
        let nameOffset = urlOffset + urlData.count
        let pathOffset = nameOffset + nameData.count
        let valueOffset = pathOffset + pathData.count
        let entrySize = valueOffset + valueData.count

        var entry = Data()
        entry.append(uint32LE(UInt32(entrySize)))
        entry.append(uint32LE(flags))
        entry.append(uint32BE(UInt32(urlOffset)))
        entry.append(uint32BE(UInt32(nameOffset)))
        entry.append(uint32BE(UInt32(pathOffset)))
        entry.append(uint32BE(UInt32(valueOffset)))
        entry.append(doubleLE(expiry))
        entry.append(doubleLE(creation))
        entry.append(uint32LE(0))
        entry.append(urlData)
        entry.append(nameData)
        entry.append(pathData)
        entry.append(valueData)
        return entry
    }

    /// Pagina in het canonieke formaat: header, cookie-telling, offsets t.o.v.
    /// de paginastart, dan de entries.
    private func makePage(entries: [Data]) -> Data {
        let offsetTableSize = 8 + entries.count * 4

        var page = Data()
        page.append(uint32LE(0x00000100))
        page.append(uint32LE(UInt32(entries.count)))
        var offset = offsetTableSize
        for entry in entries {
            page.append(uint32LE(UInt32(offset)))
            offset += entry.count
        }
        for entry in entries {
            page.append(entry)
        }
        return page
    }

    /// Bestand in het canonieke formaat: paginatelling, paginagroottes
    /// (geen absolute offsets!), pagina's sequentieel.
    private func makeFile(pages: [Data]) -> Data {
        var file = Data("cook".utf8)
        file.append(uint32LE(UInt32(pages.count)))
        for page in pages {
            file.append(uint32LE(UInt32(page.count)))
        }
        for page in pages {
            file.append(page)
        }
        return file
    }

    func testParsesFieldsCorrectly() throws {
        let reference: Double = 978_307_200
        let intervalSince2001 = 86_400.0 * 30
        let creationInterval = 100.0
        let data = makeFile(pages: [
            makePage(entries: [
                makeCookieEntry(
                    url: ".example.com",
                    name: "prefs",
                    path: "/",
                    value: "v1",
                    flags: 0x5,
                    expiry: intervalSince2001,
                    creation: creationInterval
                )
            ])
        ])

        let cookies = try BinaryCookiesParser.parse(data: data)
        XCTAssertEqual(cookies.count, 1)
        let cookie = cookies[0]
        XCTAssertEqual(cookie.domain, "example.com")
        XCTAssertEqual(cookie.name, "prefs")
        XCTAssertEqual(cookie.path, "/")
        XCTAssertTrue(cookie.isSecure)
        XCTAssertTrue(cookie.isHttpOnly)
        XCTAssertEqual(cookie.expiry?.timeIntervalSince1970 ?? 0, reference + intervalSince2001, accuracy: 1)
        XCTAssertEqual(cookie.creation?.timeIntervalSince1970 ?? 0, reference + creationInterval, accuracy: 1)
    }

    func testZeroExpiryMeansSessionCookie() throws {
        let data = makeFile(pages: [
            makePage(entries: [
                makeCookieEntry(url: "example.com", name: "sid", path: "/", value: "v", flags: 0x1, expiry: 0, creation: 0)
            ])
        ])

        let cookies = try BinaryCookiesParser.parse(data: data)
        XCTAssertNil(cookies[0].expiry)
    }

    func testMultipleCookiesAcrossPages() throws {
        let pageOne = makePage(entries: [
            makeCookieEntry(url: "site0.com", name: "c0", path: "/", value: "x", flags: 0, expiry: 1, creation: 0),
            makeCookieEntry(url: "site1.com", name: "c1", path: "/", value: "x", flags: 0, expiry: 1, creation: 0)
        ])
        let pageTwo = makePage(entries: [
            makeCookieEntry(url: "site2.com", name: "c2", path: "/", value: "x", flags: 0, expiry: 1, creation: 0)
        ])
        let cookies = try BinaryCookiesParser.parse(data: makeFile(pages: [pageOne, pageTwo]))
        XCTAssertEqual(cookies.count, 3)
        XCTAssertEqual(cookies.map(\.name), ["c0", "c1", "c2"])
    }

    func testPageSizesAreNotOffsets() throws {
        // Regressie voor het echte Safari-bestand: het eerste paginaveld is een
        // GROOTTE (bijv. 4096), geen offset. De oude parser gebruikte het als
        // absolute offset en faalde met "pagina valt buiten bestand".
        let page = makePage(entries: [
            makeCookieEntry(url: "real.com", name: "rc", path: "/", value: "x", flags: 0x0, expiry: 5, creation: 0)
        ])
        XCTAssertEqual(page.count, 8 + 4 + makeCookieEntry(url: "real.com", name: "rc", path: "/", value: "x", flags: 0, expiry: 5, creation: 0).count)

        let cookies = try BinaryCookiesParser.parse(data: makeFile(pages: [page]))
        XCTAssertEqual(cookies.map(\.name), ["rc"])
    }

    func testCorruptPageIsSkippedNotFatal() throws {
        // Pagina 2 is corrupt (cookie-telling boven de limiet): de cookies uit
        // pagina 1 moeten gewoon terugkomen, zonder throw.
        let goodPage = makePage(entries: [
            makeCookieEntry(url: "good.com", name: "gc", path: "/", value: "x", flags: 0, expiry: 1, creation: 0)
        ])

        var corruptPage = makePage(entries: [])
        corruptPage.replaceSubrange(4..<8, with: uint32LE(UInt32.max))

        let cookies = try BinaryCookiesParser.parse(data: makeFile(pages: [goodPage, corruptPage]))
        XCTAssertEqual(cookies.map(\.name), ["gc"])
    }

    func testCorruptCookieEntryIsSkipped() throws {
        // De tweede entry wijst naar offsets buiten de pagina: alleen c0 overleeft.
        let good = makeCookieEntry(url: "good.com", name: "c0", path: "/", value: "x", flags: 0, expiry: 1, creation: 0)
        var bad = makeCookieEntry(url: "bad.com", name: "c1", path: "/", value: "x", flags: 0, expiry: 1, creation: 0)
        // Zet de url-offset (big-endian, entry+8) op een absurde waarde.
        bad.replaceSubrange(8..<12, with: uint32BE(UInt32(0xFFFF_FFFF)))

        let cookies = try BinaryCookiesParser.parse(data: makeFile(pages: [makePage(entries: [good, bad])]))
        XCTAssertEqual(cookies.map(\.name), ["c0"])
    }

    func testEmptyFileAndAbsurdPageCountYieldNoCookies() throws {
        XCTAssertEqual(try BinaryCookiesParser.parse(data: makeFile(pages: [])), [])
        // pageCount=2 maar geen paginatabel aanwezig → geen crash, leeg resultaat.
        var truncated = Data("cook".utf8)
        truncated.append(uint32LE(2))
        XCTAssertEqual(try BinaryCookiesParser.parse(data: truncated), [])
    }

    func testInvalidMagicThrows() {
        var data = makeFile(pages: [])
        data.replaceSubrange(0..<4, with: Data("XXXX".utf8))
        XCTAssertThrowsError(try BinaryCookiesParser.parse(data: data))
    }
}

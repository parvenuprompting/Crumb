import XCTest
@testable import Crumb

final class BinaryCookiesParserTests: XCTestCase {
    private func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func double(_ value: Double) -> Data {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) }
    }

    private func string(_ value: String) -> Data {
        Data(value.utf8) + Data([0])
    }

    private func makeCookieEntry(
        url: String,
        name: String,
        path: String,
        value: String,
        flags: UInt32,
        expiry: Double,
        creation: Double
    ) -> Data {
        var urlData = string(url)
        var nameData = string(name)
        var pathData = string(path)
        var valueData = string(value)

        let headerSize = 44
        let urlOffset = headerSize
        let nameOffset = urlOffset + urlData.count
        let pathOffset = nameOffset + nameData.count
        let valueOffset = pathOffset + pathData.count
        let entrySize = valueOffset + valueData.count

        var entry = Data()
        entry.append(uint32(UInt32(entrySize)))
        entry.append(uint32(flags))
        entry.append(uint32(0))
        entry.append(uint32(UInt32(urlOffset)))
        entry.append(uint32(UInt32(nameOffset)))
        entry.append(uint32(UInt32(pathOffset)))
        entry.append(uint32(UInt32(valueOffset)))
        entry.append(double(expiry))
        entry.append(double(creation))
        entry.append(urlData)
        entry.append(nameData)
        entry.append(pathData)
        entry.append(valueData)
        return entry
    }

    private func makeFile(entries: [Data]) -> Data {
        let headerAndTableSize = 12 + entries.count * 4
        let pageSize = headerAndTableSize + entries.map(\.count).reduce(0, +) + 4

        var page = Data()
        page.append(uint32(0x00000100))
        page.append(uint32(UInt32(pageSize)))
        page.append(uint32(UInt32(entries.count)))
        var offset = headerAndTableSize
        for entry in entries {
            page.append(uint32(UInt32(offset)))
            offset += entry.count
        }
        for entry in entries {
            page.append(entry)
        }
        page.append(uint32(UInt32(pageSize)))

        var file = Data("cook".utf8)
        file.append(uint32(1))
        let pageOffset = 8 + 4
        file.append(uint32(UInt32(pageOffset)))
        file.append(page)
        return file
    }
    func testParsesFieldsCorrectly() throws {
        let reference: Double = 978_307_200
        let intervalSince2001 = 86_400.0 * 30
        let creationInterval = 100.0
        let data = makeFile(entries: [
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
        let data = makeFile(entries: [
            makeCookieEntry(url: "example.com", name: "sid", path: "/", value: "v", flags: 0x1, expiry: 0, creation: 0)
        ])

        let cookies = try BinaryCookiesParser.parse(data: data)
        XCTAssertNil(cookies[0].expiry)
    }

    func testMultipleCookiesAcrossPages() throws {
        let entries = (0..<3).map { index in
            makeCookieEntry(url: "site\(index).com", name: "c\(index)", path: "/", value: "x", flags: 0, expiry: 1, creation: 0)
        }
        let cookies = try BinaryCookiesParser.parse(data: makeFile(entries: entries))
        XCTAssertEqual(cookies.count, 3)
        XCTAssertEqual(cookies.map(\.name), ["c0", "c1", "c2"])
    }

    func testInvalidMagicThrows() {
        var data = makeFile(entries: [])
        data.replaceSubrange(0..<4, with: Data("XXXX".utf8))
        XCTAssertThrowsError(try BinaryCookiesParser.parse(data: data))
    }
}

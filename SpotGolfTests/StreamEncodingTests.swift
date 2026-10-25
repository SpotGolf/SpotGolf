import XCTest
@testable import SpotGolf

final class StreamEncodingTests: XCTestCase {

    /// The 2026-10-12 Broadlands round, as the 25-byte records the watch sent.
    private func broadlandsRecords() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "broadlands-2026-10-12", withExtension: "csv"))
        let export = try TrackImporter.read(String(contentsOf: url, encoding: .utf8))
        let records = export.points.map(StreamRecord.fix) + export.swings.map(StreamRecord.swing)
            + export.contacts.map(StreamRecord.contact) + export.events.map(StreamRecord.event)
        return StreamRecord.data(for: records.sorted { $0.timestamp < $1.timestamp })
    }

    func testAWholeRoundComesBackByteForByte() throws {
        let records = try broadlandsRecords()
        XCTAssertGreaterThan(records.count / StreamRecord.size, 8_000)

        let encoded = StreamEncoding.encode(records)

        XCTAssertEqual(try StreamEncoding.decode(encoded), records)
        // 25 bytes a record becomes under 10 on average
        XCTAssertLessThan(encoded.count, records.count * 4 / 10)
    }

    func testEveryKindAndExtremeValueComesBack() throws {
        var random = SystemRandomNumberGenerator()
        var records = Data()
        let extremes: [Int32] = [0, 1, -1, .max, .min, .max - 1, .min + 1]
        for index in 0..<2_000 {
            records.append(UInt8(index % 5))
            records.append(littleEndian: index % 7 == 0 ? Int64.max : index % 11 == 0 ? Int64.min : Int64(index) * 1_000)
            for word in 0..<4 {
                records.append(littleEndian: index % 3 == 0 ? extremes[(index + word) % extremes.count] : Int32.random(in: .min ... .max, using: &random))
            }
        }

        XCTAssertEqual(try StreamEncoding.decode(StreamEncoding.encode(records)), records)
    }

    func testAnEmptyStreamComesBack() throws {
        XCTAssertEqual(try StreamEncoding.decode(StreamEncoding.encode(Data())), Data())
    }

    func testAPartialRecordAtTheEndIsLeftOut() throws {
        let records = try broadlandsRecords().prefix(StreamRecord.size * 3)

        XCTAssertEqual(try StreamEncoding.decode(StreamEncoding.encode(records + Data([1, 2, 3]))), records)
    }

    func testACutOffStreamFails() throws {
        let encoded = StreamEncoding.encode(try broadlandsRecords().prefix(StreamRecord.size * 50))

        XCTAssertThrowsError(try StreamEncoding.decode(encoded.dropLast(3))) { error in
            XCTAssertEqual(error as? StreamEncoding.DecodeError, .corrupt)
        }
    }

    func testAWrongRecordCountFails() throws {
        var encoded = StreamEncoding.encode(try broadlandsRecords().prefix(StreamRecord.size * 50))
        // The count is the varint after the version byte: 50 fits in one byte
        encoded[encoded.startIndex + 1] = 49

        XCTAssertThrowsError(try StreamEncoding.decode(encoded)) { error in
            XCTAssertEqual(error as? StreamEncoding.DecodeError, .corrupt)
        }
    }

    func testANewerVersionIsRefused() throws {
        var encoded = StreamEncoding.encode(try broadlandsRecords().prefix(StreamRecord.size * 5))
        encoded[encoded.startIndex] = StreamEncoding.version + 1

        XCTAssertThrowsError(try StreamEncoding.decode(encoded)) { error in
            XCTAssertEqual(error as? StreamEncoding.DecodeError, .newerVersion(StreamEncoding.version + 1))
        }
    }
}

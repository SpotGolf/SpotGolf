import XCTest
@testable import SpotGolf

final class StreamRecordTests: XCTestCase {

    func testFixRecordIsKindByteThenTrackPoint() throws {
        let record = StreamFixtures.fix(0)
        guard case .fix(let point) = record else { return XCTFail() }

        let data = record.record

        XCTAssertEqual(data.count, 25)
        XCTAssertEqual(data.first, 0)
        XCTAssertEqual(Data(data.dropFirst()), point.record)
        XCTAssertEqual(StreamRecord(record: data), record)
    }

    func testSwingRecordHoldsTimeAndPeakForce() throws {
        let record = StreamFixtures.swing(12.345, peakG: 14.75)

        let data = record.record

        XCTAssertEqual(data.count, 25)
        XCTAssertEqual(data.first, 1)
        XCTAssertEqual(Data(data.suffix(12)), Data(count: 12))
        guard case .swing(let swing) = StreamRecord(record: data) else { return XCTFail() }
        XCTAssertEqual(swing.timestamp, StreamFixtures.start.addingTimeInterval(12.345))
        XCTAssertEqual(swing.peakG, 14.75)
    }

    func testSwingBytesAreUnchanged() {
        // Kind 1, milliseconds since 1970 as Int64, peak force as Float32, both little-endian
        let data = StreamFixtures.swing(12.345, peakG: 14.75).record
        let milliseconds = Int64(1_700_000_012_345)
        var expected = Data([1])
        expected.append(contentsOf: withUnsafeBytes(of: milliseconds.littleEndian, Array.init))
        expected.append(contentsOf: withUnsafeBytes(of: Float(14.75).bitPattern.littleEndian, Array.init))
        expected.append(Data(count: 12))

        XCTAssertEqual(data, expected)
    }

    func testUnknownKindOrWrongSizeIsNotARecord() {
        var data = StreamFixtures.fix(0).record
        data[data.startIndex] = 7
        XCTAssertNil(StreamRecord(record: data))
        XCTAssertNil(StreamRecord(record: Data(count: 24)))
    }

    func testRecordsSplitBackToBackDataAndDropAPartialRecord() {
        let records = [StreamFixtures.fix(0), StreamFixtures.swing(1), StreamFixtures.fix(2)]
        var data = StreamRecord.data(for: records)
        data.append(Data(count: 10))

        XCTAssertEqual(StreamRecord.records(in: data), records)
    }
}

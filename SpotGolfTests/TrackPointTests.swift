import XCTest
import CoreLocation
@testable import SpotGolf

final class TrackPointTests: XCTestCase {

    private func makePoint(seconds: TimeInterval = 1_700_000_000.5, altitude: Double? = 1620.5,
                           accuracy: Double? = 4.5) -> TrackPoint {
        TrackPoint(timestamp: Date(timeIntervalSince1970: seconds),
                   latitude: 39.95545,
                   longitude: -105.0422,
                   altitude: altitude,
                   horizontalAccuracy: accuracy)
    }

    private func makeLocation(verticalAccuracy: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39.95545, longitude: -105.0422),
                   altitude: 1620,
                   horizontalAccuracy: 5,
                   verticalAccuracy: verticalAccuracy,
                   course: 90,
                   speed: 1.5,
                   timestamp: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testInitFromLocation() {
        let point = TrackPoint(location: makeLocation(verticalAccuracy: 3))

        XCTAssertEqual(point.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(point.latitude, 39.95545)
        XCTAssertEqual(point.longitude, -105.0422)
        XCTAssertEqual(point.altitude, 1620)
        XCTAssertEqual(point.horizontalAccuracy, 5)
    }

    func testInitFromLocationWithoutValidAltitude() {
        XCTAssertNil(TrackPoint(location: makeLocation(verticalAccuracy: -1)).altitude)
    }

    func testRecordLayout() {
        let record = makePoint().record

        XCTAssertEqual(record.count, TrackPoint.recordSize)
        XCTAssertEqual(record.littleEndianInteger(at: 0) as Int64, 1_700_000_000_500)
        XCTAssertEqual(record.littleEndianInteger(at: 8) as Int32, 399_554_500)
        XCTAssertEqual(record.littleEndianInteger(at: 12) as Int32, -1_050_422_000)
        XCTAssertEqual(record.littleEndianInteger(at: 16) as Int32, 162_050)
        XCTAssertEqual(record.littleEndianInteger(at: 20) as Int32, 450)
    }

    func testRecordIsLittleEndian() {
        let record = makePoint(seconds: 1).record
        XCTAssertEqual(Array(record.prefix(8)), [0xE8, 0x03, 0, 0, 0, 0, 0, 0])
    }

    func testRecordRoundTrip() {
        let point = makePoint()
        XCTAssertEqual(TrackPoint(record: point.record), point)
    }

    func testRecordRoundTripWithoutAltitude() {
        let point = makePoint(altitude: nil)
        XCTAssertEqual(TrackPoint(record: point.record), point)
    }

    func testRecordRoundTripWithoutAccuracy() {
        let point = makePoint(accuracy: nil)
        XCTAssertEqual(TrackPoint(record: point.record), point)
    }

    func testRecordRoundTripBelowSeaLevel() {
        let point = makePoint(altitude: -86.2)
        XCTAssertEqual(TrackPoint(record: point.record), point)
    }

    func testRecordRoundsToStoredPrecision() {
        let point = TrackPoint(timestamp: Date(timeIntervalSince1970: 1_700_000_000.1234),
                               latitude: 39.955450049,
                               longitude: -105.042200049,
                               altitude: 1620.504)

        XCTAssertEqual(TrackPoint(record: point.record),
                       TrackPoint(timestamp: Date(timeIntervalSince1970: 1_700_000_000.123),
                                  latitude: 39.95545,
                                  longitude: -105.0422,
                                  altitude: 1620.5))
    }

    func testAccuracyRoundsToStoredPrecision() {
        let point = makePoint(accuracy: 4.567)
        XCTAssertEqual(TrackPoint(record: point.record)?.horizontalAccuracy, 4.57)
    }

    func testReadsFromTheMiddleOfLargerData() {
        let point = makePoint()
        let data = Data([1, 2, 3, 4]) + point.record + Data([5, 6])
        let slice = data[4..<(4 + TrackPoint.recordSize)]

        XCTAssertEqual(TrackPoint(record: slice), point)
    }

    func testWrongSizeIsNotAPoint() {
        XCTAssertNil(TrackPoint(record: Data()))
        XCTAssertNil(TrackPoint(record: makePoint().record.dropLast()))
        XCTAssertNil(TrackPoint(record: makePoint().record + Data([0])))
    }
}

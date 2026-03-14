import XCTest
import CoreLocation
@testable import SpotGolf

final class BallMarkTests: XCTestCase {

    func testInitWithDefaults() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(coordinate: coord)

        XCTAssertEqual(mark.latitude, 33.45)
        XCTAssertEqual(mark.longitude, -112.07)
        XCTAssertNotNil(mark.id)
    }

    func testInitWithExplicitValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let coord = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        let mark = BallMark(id: id, coordinate: coord, timestamp: date)

        XCTAssertEqual(mark.id, id)
        XCTAssertEqual(mark.latitude, 40.0)
        XCTAssertEqual(mark.longitude, -74.0)
        XCTAssertEqual(mark.timestamp, date)
    }

    func testCoordinateComputedProperty() {
        let coord = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)
        let mark = BallMark(coordinate: coord)

        XCTAssertEqual(mark.coordinate.latitude, 51.5)
        XCTAssertEqual(mark.coordinate.longitude, -0.12)
    }

    func testLocationComputedProperty() {
        let coord = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.69)
        let mark = BallMark(coordinate: coord)

        XCTAssertEqual(mark.location.coordinate.latitude, 35.68)
        XCTAssertEqual(mark.location.coordinate.longitude, 139.69)
    }

    func testCodableRoundTrip() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(id: id, coordinate: coord, timestamp: date)

        let data = try JSONEncoder().encode(mark)
        let decoded = try JSONDecoder().decode(BallMark.self, from: data)

        XCTAssertEqual(decoded.id, mark.id)
        XCTAssertEqual(decoded.latitude, mark.latitude)
        XCTAssertEqual(decoded.longitude, mark.longitude)
        XCTAssertEqual(decoded.timestamp, mark.timestamp)
    }

    func testEquatable() {
        let id = UUID()
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let date = Date()
        let mark1 = BallMark(id: id, coordinate: coord, timestamp: date)
        let mark2 = BallMark(id: id, coordinate: coord, timestamp: date)

        XCTAssertEqual(mark1, mark2)
    }

    func testNotEqualWithDifferentIDs() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let date = Date()
        let mark1 = BallMark(id: UUID(), coordinate: coord, timestamp: date)
        let mark2 = BallMark(id: UUID(), coordinate: coord, timestamp: date)

        XCTAssertNotEqual(mark1, mark2)
    }

    func testNotEqualWithDifferentCoordinates() {
        let id = UUID()
        let date = Date()
        let mark1 = BallMark(id: id, coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0), timestamp: date)
        let mark2 = BallMark(id: id, coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -112.0), timestamp: date)

        XCTAssertNotEqual(mark1, mark2)
    }

    // MARK: - BallMarkType

    func testDefaultTypeIsRegular() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(coordinate: coord)

        XCTAssertEqual(mark.type, .regular)
    }

    func testInitWithPenaltyType() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(coordinate: coord, type: .penalty)

        XCTAssertEqual(mark.type, .penalty)
    }

    func testInitWithOutOfBoundsType() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(coordinate: coord, type: .outOfBounds)

        XCTAssertEqual(mark.type, .outOfBounds)
    }

    func testCodableRoundTripWithType() throws {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(coordinate: coord, type: .penalty)

        let data = try JSONEncoder().encode(mark)
        let decoded = try JSONDecoder().decode(BallMark.self, from: data)

        XCTAssertEqual(decoded.type, .penalty)
    }

    func testCodableBackwardCompatibility() throws {
        // Simulate legacy JSON without a "type" field
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","latitude":33.45,"longitude":-112.07,"timestamp":0}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BallMark.self, from: data)

        XCTAssertEqual(decoded.type, .regular)
    }

    func testNotEqualWithDifferentTypes() {
        let id = UUID()
        let date = Date()
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark1 = BallMark(id: id, coordinate: coord, timestamp: date, type: .regular)
        let mark2 = BallMark(id: id, coordinate: coord, timestamp: date, type: .penalty)

        XCTAssertNotEqual(mark1, mark2)
    }
}

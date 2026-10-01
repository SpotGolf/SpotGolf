import XCTest
import CoreLocation
@testable import SpotGolf

final class StrokeTests: XCTestCase {

    func testInitWithDefaults() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(coordinate: coord)

        XCTAssertEqual(stroke.latitude, 33.45)
        XCTAssertEqual(stroke.longitude, -112.07)
        XCTAssertNotNil(stroke.id)
    }

    func testInitWithExplicitValues() {
        let id = UUID()
        let coord = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        let stroke = Stroke(id: id, coordinate: coord)

        XCTAssertEqual(stroke.id, id)
        XCTAssertEqual(stroke.latitude, 40.0)
        XCTAssertEqual(stroke.longitude, -74.0)
    }

    func testCoordinateComputedProperty() {
        let coord = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)
        let stroke = Stroke(coordinate: coord)

        XCTAssertEqual(stroke.coordinate.latitude, 51.5)
        XCTAssertEqual(stroke.coordinate.longitude, -0.12)
    }

    func testLocationComputedProperty() {
        let coord = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.69)
        let stroke = Stroke(coordinate: coord)

        XCTAssertEqual(stroke.location.coordinate.latitude, 35.68)
        XCTAssertEqual(stroke.location.coordinate.longitude, 139.69)
    }

    func testCodableRoundTrip() throws {
        let id = UUID()
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(id: id, coordinate: coord)

        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(Stroke.self, from: data)

        XCTAssertEqual(decoded.id, stroke.id)
        XCTAssertEqual(decoded.latitude, stroke.latitude)
        XCTAssertEqual(decoded.longitude, stroke.longitude)
    }

    func testEquatable() {
        let id = UUID()
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke1 = Stroke(id: id, coordinate: coord)
        let stroke2 = Stroke(id: id, coordinate: coord)

        XCTAssertEqual(stroke1, stroke2)
    }

    func testNotEqualWithDifferentIDs() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke1 = Stroke(id: UUID(), coordinate: coord)
        let stroke2 = Stroke(id: UUID(), coordinate: coord)

        XCTAssertNotEqual(stroke1, stroke2)
    }

    func testNotEqualWithDifferentCoordinates() {
        let id = UUID()
        let stroke1 = Stroke(id: id, coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(id: id, coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -112.0))

        XCTAssertNotEqual(stroke1, stroke2)
    }

    // MARK: - StrokeType

    func testDefaultTypeIsRegular() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(coordinate: coord)

        XCTAssertEqual(stroke.type, .regular)
    }

    func testInitWithPenaltyType() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(coordinate: coord, type: .penalty)

        XCTAssertEqual(stroke.type, .penalty)
    }

    func testInitWithOutOfBoundsType() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(coordinate: coord, type: .outOfBounds)

        XCTAssertEqual(stroke.type, .outOfBounds)
    }

    func testCodableRoundTripWithType() throws {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(coordinate: coord, type: .penalty)

        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(Stroke.self, from: data)

        XCTAssertEqual(decoded.type, .penalty)
    }

    func testNotEqualWithDifferentTypes() {
        let id = UUID()
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke1 = Stroke(id: id, coordinate: coord, type: .regular)
        let stroke2 = Stroke(id: id, coordinate: coord, type: .penalty)

        XCTAssertNotEqual(stroke1, stroke2)
    }
}

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

    func testClubRoundTripsAndOldStrokesDecodeWithoutOne() throws {
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07), club: Club.named("7i"))

        let decoded = try JSONDecoder().decode(Stroke.self, from: JSONEncoder().encode(stroke))
        XCTAssertEqual(decoded.club?.id, "7i")
        XCTAssertEqual(decoded, stroke)

        let old = """
        {"id":"\(UUID().uuidString)","latitude":33.45,"longitude":-112.07,"origin":{"manual":{}},"type":"regular"}
        """
        let oldStroke = try JSONDecoder().decode(Stroke.self, from: Data(old.utf8))
        XCTAssertNil(oldStroke.club)
        XCTAssertNil(oldStroke.clubID)
    }

    func testOriginAndHitTimeRoundTrip() throws {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let strokes = [
            Stroke(coordinate: coord),
            Stroke(coordinate: coord, hitAt: Date(timeIntervalSince1970: 1_700_000_000)),
            Stroke(coordinate: coord, origin: .suggestion(id: UUID()), hitAt: Date(timeIntervalSince1970: 1_700_000_100)),
        ]

        for stroke in strokes {
            XCTAssertEqual(try JSONDecoder().decode(Stroke.self, from: JSONEncoder().encode(stroke)), stroke)
        }
        XCTAssertEqual(strokes[0].origin, .manual)
        XCTAssertNil(strokes[0].hitAt)
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

    // MARK: - Penalty strokes

    func testDefaultHasNoPenaltyStrokesAndScoresOne() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(coordinate: coord)

        XCTAssertEqual(stroke.penaltyStrokes, 0)
        XCTAssertEqual(stroke.score, 1)
    }

    func testPenaltyStrokesAddToTheScoreAndStopAtTheMost() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)

        XCTAssertEqual(Stroke(coordinate: coord, penaltyStrokes: 2).score, 3)
        XCTAssertEqual(Stroke(coordinate: coord, penaltyStrokes: 9).penaltyStrokes, Stroke.maxPenaltyStrokes)
        XCTAssertEqual(Stroke(coordinate: coord, penaltyStrokes: -1).penaltyStrokes, 0)
    }

    func testCodableRoundTripWithPenaltyStrokes() throws {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke = Stroke(coordinate: coord, penaltyStrokes: 2)

        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(Stroke.self, from: data)

        XCTAssertEqual(decoded.penaltyStrokes, 2)
        XCTAssertEqual(decoded, stroke)
    }

    func testOldStrokesDecodeTheirTypeAsPenaltyStrokes() throws {
        func decode(type: String) throws -> Stroke {
            let json = """
            {"id":"\(UUID().uuidString)","latitude":33.45,"longitude":-112.07,"origin":{"manual":{}},"type":"\(type)"}
            """
            return try JSONDecoder().decode(Stroke.self, from: Data(json.utf8))
        }

        XCTAssertEqual(try decode(type: "regular").penaltyStrokes, 0)
        XCTAssertEqual(try decode(type: "penalty").penaltyStrokes, 1)
        XCTAssertEqual(try decode(type: "outOfBounds").penaltyStrokes, 1)
    }

    func testQualityRoundTripsAndOldStrokesAreUnrated() throws {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        XCTAssertEqual(Stroke(coordinate: coord).quality, .good)

        let stroke = Stroke(coordinate: coord, quality: .okay)
        let decoded = try JSONDecoder().decode(Stroke.self, from: JSONEncoder().encode(stroke))
        XCTAssertEqual(decoded.quality, .okay)
        XCTAssertEqual(decoded, stroke)

        let old = """
        {"id":"\(UUID().uuidString)","latitude":33.45,"longitude":-112.07,"origin":{"manual":{}},"penaltyStrokes":1}
        """
        XCTAssertEqual(try JSONDecoder().decode(Stroke.self, from: Data(old.utf8)).quality, .unrated)
    }

    func testNotEqualWithDifferentPenaltyStrokes() {
        let id = UUID()
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let stroke1 = Stroke(id: id, coordinate: coord)
        let stroke2 = Stroke(id: id, coordinate: coord, penaltyStrokes: 1)

        XCTAssertNotEqual(stroke1, stroke2)
    }
}

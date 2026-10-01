import XCTest
import CoreLocation
@testable import SpotGolf

final class HoleTests: XCTestCase {

    func testInitDefaults() {
        let hole = RoundHole()

        XCTAssertNotNil(hole.id)
        XCTAssertTrue(hole.strokes.isEmpty)
    }

    func testInitWithExplicitValues() {
        let id = UUID()
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let hole = RoundHole(id: id, strokes: [stroke])

        XCTAssertEqual(hole.id, id)
        XCTAssertEqual(hole.strokes.count, 1)
        XCTAssertEqual(hole.strokes[0].id, stroke.id)
    }

    func testStrokeCountEmpty() {
        let hole = RoundHole()

        XCTAssertEqual(hole.strokeCount, 0)
    }

    func testStrokeCountOneStroke() {
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let hole = RoundHole(strokes: [stroke])

        XCTAssertEqual(hole.strokeCount, 1)
    }

    func testStrokeCountMultipleStrokes() {
        let stroke1 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let stroke3 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: -114.0))
        let hole = RoundHole(strokes: [stroke1, stroke2, stroke3])

        XCTAssertEqual(hole.strokeCount, 3)
    }

    func testCodableRoundTrip() throws {
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let hole = RoundHole(strokes: [stroke])

        let data = try JSONEncoder().encode(hole)
        let decoded = try JSONDecoder().decode(RoundHole.self, from: data)

        XCTAssertEqual(decoded.id, hole.id)
        XCTAssertEqual(decoded.strokes.count, 1)
        XCTAssertEqual(decoded.strokes[0].id, stroke.id)
    }

    func testEquatable() {
        let id = UUID()
        let hole1 = RoundHole(id: id)
        let hole2 = RoundHole(id: id)

        XCTAssertEqual(hole1, hole2)
    }
}

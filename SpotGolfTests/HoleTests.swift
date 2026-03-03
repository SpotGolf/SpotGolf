import XCTest
import CoreLocation
@testable import SpotGolf

final class HoleTests: XCTestCase {

    func testInitDefaults() {
        let hole = Hole()

        XCTAssertNotNil(hole.id)
        XCTAssertTrue(hole.marks.isEmpty)
    }

    func testInitWithExplicitValues() {
        let id = UUID()
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let hole = Hole(id: id, marks: [mark])

        XCTAssertEqual(hole.id, id)
        XCTAssertEqual(hole.marks.count, 1)
        XCTAssertEqual(hole.marks[0].id, mark.id)
    }

    func testStrokeCountEmpty() {
        let hole = Hole()

        XCTAssertEqual(hole.strokeCount, 0)
    }

    func testStrokeCountOneMark() {
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let hole = Hole(marks: [mark])

        XCTAssertEqual(hole.strokeCount, 0)
    }

    func testStrokeCountMultipleMarks() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let mark3 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: -114.0))
        let hole = Hole(marks: [mark1, mark2, mark3])

        XCTAssertEqual(hole.strokeCount, 2)
    }

    func testCodableRoundTrip() throws {
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let hole = Hole(marks: [mark])

        let data = try JSONEncoder().encode(hole)
        let decoded = try JSONDecoder().decode(Hole.self, from: data)

        XCTAssertEqual(decoded.id, hole.id)
        XCTAssertEqual(decoded.marks.count, 1)
        XCTAssertEqual(decoded.marks[0].id, mark.id)
    }

    func testEquatable() {
        let id = UUID()
        let hole1 = Hole(id: id)
        let hole2 = Hole(id: id)

        XCTAssertEqual(hole1, hole2)
    }
}

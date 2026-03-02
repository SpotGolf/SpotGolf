import XCTest
import CoreLocation
@testable import SpotGolf

final class RoundTests: XCTestCase {

    func testInitDefaults() {
        let round = Round()

        XCTAssertTrue(round.isActive)
        XCTAssertTrue(round.marks.isEmpty)
        XCTAssertNotNil(round.id)
    }

    func testInitWithExplicitValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let round = Round(id: id, date: date, marks: [mark], isActive: false)

        XCTAssertEqual(round.id, id)
        XCTAssertEqual(round.date, date)
        XCTAssertEqual(round.marks.count, 1)
        XCTAssertFalse(round.isActive)
    }

    func testAddMark() {
        var round = Round()
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))

        round.addMark(mark)

        XCTAssertEqual(round.marks.count, 1)
        XCTAssertEqual(round.marks[0].id, mark.id)
    }

    func testAddMultipleMarks() {
        var round = Round()
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))

        round.addMark(mark1)
        round.addMark(mark2)

        XCTAssertEqual(round.marks.count, 2)
        XCTAssertEqual(round.marks[0].id, mark1.id)
        XCTAssertEqual(round.marks[1].id, mark2.id)
    }

    func testEnd() {
        var round = Round()
        XCTAssertTrue(round.isActive)

        round.end()
        XCTAssertFalse(round.isActive)
    }

    func testFormattedDate() {
        let round = Round()
        let formatted = round.formattedDate

        // formattedDate should produce a non-empty string
        XCTAssertFalse(formatted.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var round = Round()
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        round.addMark(mark)

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.id, round.id)
        XCTAssertEqual(decoded.date, round.date)
        XCTAssertEqual(decoded.marks.count, 1)
        XCTAssertEqual(decoded.marks[0].id, mark.id)
        XCTAssertEqual(decoded.isActive, round.isActive)
    }

    func testCodableRoundTripEndedRound() throws {
        var round = Round()
        round.end()

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertFalse(decoded.isActive)
    }
}

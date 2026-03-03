import XCTest
import CoreLocation
@testable import SpotGolf

final class RoundTests: XCTestCase {

    func testInitDefaults() {
        let round = Round()

        XCTAssertTrue(round.isActive)
        XCTAssertTrue(round.marks.isEmpty)
        XCTAssertNotNil(round.id)
        XCTAssertEqual(round.holes.count, 1)
        XCTAssertEqual(round.currentHoleIndex, 0)
    }

    func testInitWithExplicitValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let hole = Hole(marks: [mark])
        let round = Round(id: id, date: date, holes: [hole], isActive: false)

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

    // MARK: - Hole navigation

    func testCurrentHoleNumber() {
        let round = Round()

        XCTAssertEqual(round.currentHoleNumber, 1)
    }

    func testNextHoleAppendsAndAdvances() {
        var round = Round()
        round.addMark(BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0)))

        round.nextHole()

        XCTAssertEqual(round.holes.count, 2)
        XCTAssertEqual(round.currentHoleIndex, 1)
        XCTAssertEqual(round.currentHoleNumber, 2)
        XCTAssertTrue(round.marks.isEmpty) // new hole has no marks
    }

    func testNextHoleDoesNotExceed18() {
        var round = Round(holes: (0..<18).map { _ in Hole() }, currentHoleIndex: 17)

        round.nextHole()

        XCTAssertEqual(round.holes.count, 18)
        XCTAssertEqual(round.currentHoleIndex, 17) // stays on hole 18
    }

    func testNextHoleAdvancesWithoutAppendingWhenNotOnLast() {
        var round = Round(holes: [Hole(), Hole(), Hole()], currentHoleIndex: 0)

        round.nextHole()

        XCTAssertEqual(round.holes.count, 3) // no new hole appended
        XCTAssertEqual(round.currentHoleIndex, 1)
    }

    func testPreviousHole() {
        var round = Round(holes: [Hole(), Hole()], currentHoleIndex: 1)

        round.previousHole()

        XCTAssertEqual(round.currentHoleIndex, 0)
    }

    func testPreviousHoleClampsAtZero() {
        var round = Round()

        round.previousHole()

        XCTAssertEqual(round.currentHoleIndex, 0)
    }

    func testMarksReturnsCurrentHoleMarks() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = Hole(marks: [mark1])
        let hole2 = Hole(marks: [mark2])
        let round = Round(holes: [hole1, hole2], currentHoleIndex: 1)

        XCTAssertEqual(round.marks.count, 1)
        XCTAssertEqual(round.marks[0].id, mark2.id)
    }

    func testAllMarks() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = Hole(marks: [mark1])
        let hole2 = Hole(marks: [mark2])
        let round = Round(holes: [hole1, hole2])

        XCTAssertEqual(round.allMarks.count, 2)
    }

    func testHoleIndexContaining() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = Hole(marks: [mark1])
        let hole2 = Hole(marks: [mark2])
        let round = Round(holes: [hole1, hole2])

        XCTAssertEqual(round.holeIndex(containing: mark1.id), 0)
        XCTAssertEqual(round.holeIndex(containing: mark2.id), 1)
        XCTAssertNil(round.holeIndex(containing: UUID()))
    }

    func testAddMarkAppendsToCurrentHole() {
        var round = Round(holes: [Hole(), Hole()], currentHoleIndex: 1)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))

        round.addMark(mark)

        XCTAssertTrue(round.holes[0].marks.isEmpty)
        XCTAssertEqual(round.holes[1].marks.count, 1)
    }

    // MARK: - Legacy Codable compatibility

    func testDecodeLegacyFormat() throws {
        // Simulate the old format: flat marks array, no holes
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markData = try JSONEncoder().encode(mark)
        let markJSON = String(data: markData, encoding: .utf8)!

        let json = """
        {
            "id": "\(UUID().uuidString)",
            "date": 1000000.0,
            "marks": [\(markJSON)],
            "isActive": true
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.holes.count, 1)
        XCTAssertEqual(decoded.holes[0].marks.count, 1)
        XCTAssertEqual(decoded.currentHoleIndex, 0)
    }

    func testCodableRoundTripWithMultipleHoles() throws {
        var round = Round()
        round.addMark(BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0)))
        round.nextHole()
        round.addMark(BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0)))

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.holes.count, 2)
        XCTAssertEqual(decoded.currentHoleIndex, 1)
        XCTAssertEqual(decoded.holes[0].marks.count, 1)
        XCTAssertEqual(decoded.holes[1].marks.count, 1)
    }
}

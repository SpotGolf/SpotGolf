import XCTest
import CoreLocation
import CourseDataSwift
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
        let hole = RoundHole(marks: [mark])
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

    func testNextHoleDoesNotExceedMaxHoles() {
        var round = Round(holes: (0..<Round.maxHoles).map { _ in RoundHole() }, currentHoleIndex: Round.maxHoles - 1)

        let changed = round.nextHole()

        XCTAssertFalse(changed)
        XCTAssertEqual(round.holes.count, Round.maxHoles)
        XCTAssertEqual(round.currentHoleIndex, Round.maxHoles - 1)
    }

    func testNextHoleAdvancesWithoutAppendingWhenNotOnLast() {
        var round = Round(holes: [RoundHole(), RoundHole(), RoundHole()], currentHoleIndex: 0)

        round.nextHole()

        XCTAssertEqual(round.holes.count, 3) // no new hole appended
        XCTAssertEqual(round.currentHoleIndex, 1)
    }

    func testPreviousHole() {
        var round = Round(holes: [RoundHole(), RoundHole()], currentHoleIndex: 1)

        round.previousHole()

        XCTAssertEqual(round.currentHoleIndex, 0)
    }

    func testPreviousHoleClampsAtZero() {
        var round = Round()

        let changed = round.previousHole()

        XCTAssertFalse(changed)
        XCTAssertEqual(round.currentHoleIndex, 0)
    }

    func testMarksReturnsCurrentHoleMarks() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = RoundHole(marks: [mark1])
        let hole2 = RoundHole(marks: [mark2])
        let round = Round(holes: [hole1, hole2], currentHoleIndex: 1)

        XCTAssertEqual(round.marks.count, 1)
        XCTAssertEqual(round.marks[0].id, mark2.id)
    }

    func testAllMarks() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = RoundHole(marks: [mark1])
        let hole2 = RoundHole(marks: [mark2])
        let round = Round(holes: [hole1, hole2])

        XCTAssertEqual(round.allMarks.count, 2)
    }

    func testHoleIndexContaining() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = RoundHole(marks: [mark1])
        let hole2 = RoundHole(marks: [mark2])
        let round = Round(holes: [hole1, hole2])

        XCTAssertEqual(round.holeIndex(containing: mark1.id), 0)
        XCTAssertEqual(round.holeIndex(containing: mark2.id), 1)
        XCTAssertNil(round.holeIndex(containing: UUID()))
    }

    func testAddMarkAppendsToCurrentHole() {
        var round = Round(holes: [RoundHole(), RoundHole()], currentHoleIndex: 1)
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

    func testEndTrimsTrailingEmptyHoles() {
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        var round = Round(holes: [RoundHole(marks: [mark]), RoundHole(), RoundHole()], currentHoleIndex: 2)

        round.end()

        XCTAssertEqual(round.holes.count, 1)
        XCTAssertEqual(round.currentHoleIndex, 0)
        XCTAssertFalse(round.isActive)
    }

    func testEndPreservesNonEmptyHoles() {
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        var round = Round(holes: [RoundHole(marks: [mark1]), RoundHole(marks: [mark2])], currentHoleIndex: 1)

        round.end()

        XCTAssertEqual(round.holes.count, 2)
        XCTAssertEqual(round.currentHoleIndex, 1)
    }

    func testDecoderClampsOutOfBoundsIndex() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "date": 1000000.0,
            "holes": [{"id": "\(UUID().uuidString)", "marks": []}],
            "currentHoleIndex": 99,
            "isActive": true
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.currentHoleIndex, 0)
    }

    func testNextHoleReturnsTrueWhenAdvanced() {
        var round = Round()

        let changed = round.nextHole()

        XCTAssertTrue(changed)
        XCTAssertEqual(round.currentHoleIndex, 1)
    }

    func testPreviousHoleReturnsTrueWhenMoved() {
        var round = Round(holes: [RoundHole(), RoundHole()], currentHoleIndex: 1)

        let changed = round.previousHole()

        XCTAssertTrue(changed)
        XCTAssertEqual(round.currentHoleIndex, 0)
    }

    // MARK: - Course data

    private func makeCourseSelection() -> CourseSelection {
        let greenFeature = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.0, longitude: -112.0),
            Coordinate(latitude: 33.0, longitude: -112.002),
            Coordinate(latitude: 33.002, longitude: -112.002),
            Coordinate(latitude: 33.002, longitude: -112.0),
            Coordinate(latitude: 33.0, longitude: -112.0),
        ])
        let hole1 = Hole(number: 1, par: 4, features: [1], tees: [:], centerline: [])
        let hole2 = Hole(number: 2, par: 3, features: [1], tees: [:], centerline: [])
        let subCourse = SubCourse(name: "Front", holes: [hole1, hole2])
        let location = CourseLocation(address: "", city: "Phoenix", state: "AZ", country: "US",
                                      coordinate: Coordinate(latitude: 33.0, longitude: -112.0))
        let course = Course(name: "Test Course", clubName: "Test Club",
                            location: location, features: [greenFeature], subCourses: [subCourse])
        return CourseSelection(course: course, selectedSubCourseIndices: [0])
    }

    func testRoundWithCourseData() {
        let selection = makeCourseSelection()
        let round = Round(courseSelection: selection)

        XCTAssertNotNil(round.courseSelection)
        XCTAssertEqual(round.courseSelection?.course.name, "Test Course")
        XCTAssertEqual(round.courseSelection?.selectedSubCourseIndices, [0])
    }

    func testRoundWithoutCourseData() {
        let round = Round()

        XCTAssertNil(round.courseSelection)
    }

    func testRoundCourseSelectionEncodeDecode() throws {
        let selection = makeCourseSelection()
        let round = Round(courseSelection: selection)

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.courseSelection, selection)
        XCTAssertEqual(decoded.courseSelection?.course.name, "Test Course")
        XCTAssertEqual(decoded.courseSelection?.orderedHoles.count, 2)
    }

    func testCurrentCourseHole() {
        let selection = makeCourseSelection()
        var round = Round(courseSelection: selection)

        XCTAssertEqual(round.currentCourseHole?.id, 1)
        XCTAssertEqual(round.currentCourseHole?.par, 4)

        round.nextHole()

        XCTAssertEqual(round.currentCourseHole?.id, 2)
        XCTAssertEqual(round.currentCourseHole?.par, 3)

        // Beyond available course holes
        round.nextHole()

        XCTAssertNil(round.currentCourseHole)
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

    // MARK: - Course name shortening

    func testShortenGolfCourse() {
        XCTAssertEqual(Round.shortenCourseName("Broadlands Golf Course"), "Broadlands GC")
    }

    func testShortenGolfClub() {
        XCTAssertEqual(Round.shortenCourseName("Pine Valley Golf Club"), "Pine Valley GC")
    }

    func testShortenGolfResort() {
        XCTAssertEqual(Round.shortenCourseName("Omni Interlocken Golf Resort"), "Omni Interlocken GC")
    }

    func testShortenResort() {
        XCTAssertEqual(Round.shortenCourseName("Pebble Beach Resort"), "Pebble Beach Resort")
    }

    func testShortenCountryClub() {
        XCTAssertEqual(Round.shortenCourseName("Augusta National Country Club"), "Augusta National CC")
    }

    func testShortenStripThe() {
        XCTAssertEqual(Round.shortenCourseName("The Olympic Club"), "Olympic Club")
    }

    func testShortenStripTheClubAt() {
        XCTAssertEqual(Round.shortenCourseName("The Club at Pradera"), "Pradera")
    }

    func testShortenCombinedPrefixAndSuffix() {
        XCTAssertEqual(Round.shortenCourseName("The Broadlands Golf Course"), "Broadlands GC")
    }

    func testShortenNoChange() {
        XCTAssertEqual(Round.shortenCourseName("Pebble Beach"), "Pebble Beach")
    }

    func testShortenEmptyString() {
        XCTAssertEqual(Round.shortenCourseName(""), "")
    }

    func testShortenTheCountryClub() {
        XCTAssertEqual(Round.shortenCourseName("The Country Club"), "CC")
    }

    func testShortenCaseInsensitive() {
        XCTAssertEqual(Round.shortenCourseName("the broadlands golf course"), "broadlands GC")
    }

    // MARK: - Duplicate mark detection

    func testAddMarkIgnoresDuplicate() {
        var round = Round()
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        round.addMark(mark)
        round.addMark(mark) // same UUID

        XCTAssertEqual(round.marks.count, 1)
    }

    func testAddMarkToHoleIgnoresDuplicate() {
        var round = Round()
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        round.addMark(mark, toHoleIndex: 0)
        round.addMark(mark, toHoleIndex: 0) // same UUID

        XCTAssertEqual(round.holes[0].marks.count, 1)
    }

    func testAddMarkToHoleIgnoresDuplicateAcrossHoles() {
        var round = Round(holes: [RoundHole(), RoundHole()])
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        round.addMark(mark, toHoleIndex: 0)
        round.addMark(mark, toHoleIndex: 1) // same UUID, different hole

        XCTAssertEqual(round.holes[0].marks.count, 1)
        XCTAssertEqual(round.holes[1].marks.count, 0)
    }
}

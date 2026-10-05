import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

final class RoundTests: XCTestCase {

    func testInitDefaults() {
        let round = Round(courseSelection: .test)

        XCTAssertTrue(round.isActive)
        XCTAssertTrue(round.displayHoleStrokes.isEmpty)
        XCTAssertNotNil(round.id)
        XCTAssertEqual(round.holes.count, 1)
        XCTAssertEqual(round.displayHoleIndex, 0)
    }

    func testInitWithExplicitValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let hole = RoundHole(strokes: [stroke])
        let round = Round(id: id, date: date, holes: [hole], status: .ended, courseSelection: .test)

        XCTAssertEqual(round.id, id)
        XCTAssertEqual(round.date, date)
        XCTAssertEqual(round.displayHoleStrokes.count, 1)
        XCTAssertFalse(round.isActive)
        XCTAssertFalse(round.isInProgress)
    }

    func testTimelineStartsOnFirstHoleAtRoundDate() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let round = Round(date: date, courseSelection: .test)

        XCTAssertEqual(round.holeTimeline.count, 1)
        XCTAssertEqual(round.holeTimeline[0].holeIndex, 0)
        XCTAssertEqual(round.holeTimeline[0].startedAt, date)
        XCTAssertEqual(round.holeTimeline[0].source, .roundStart)
    }

    func testStartingAndEndingRoundsAreInProgressButNotActive() {
        for status in [RoundStatus.starting, .ending] {
            let round = Round(status: status, courseSelection: .test)
            XCTAssertFalse(round.isActive)
            XCTAssertTrue(round.isInProgress)
        }
    }

    func testAddStroke() {
        var round = Round(courseSelection: .test)
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))

        round.addStroke(stroke, toHoleIndex: 0)

        XCTAssertEqual(round.displayHoleStrokes.count, 1)
        XCTAssertEqual(round.displayHoleStrokes[0].id, stroke.id)
    }

    func testAddMultipleStrokes() {
        var round = Round(courseSelection: .test)
        let stroke1 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))

        round.addStroke(stroke1, toHoleIndex: 0)
        round.addStroke(stroke2, toHoleIndex: 0)

        XCTAssertEqual(round.displayHoleStrokes.count, 2)
        XCTAssertEqual(round.displayHoleStrokes[0].id, stroke1.id)
        XCTAssertEqual(round.displayHoleStrokes[1].id, stroke2.id)
    }

    func testEnd() {
        var round = Round(courseSelection: .test)
        XCTAssertTrue(round.isActive)

        let endedAt = Date(timeIntervalSince1970: 1_000_000)
        round.end(at: endedAt)
        XCTAssertFalse(round.isActive)
        XCTAssertEqual(round.status, .ended)
        XCTAssertEqual(round.endedAt, endedAt)
    }

    func testEndKeepsEarlierEndTime() {
        var round = Round(courseSelection: .test)
        let first = Date(timeIntervalSince1970: 1_000_000)
        round.endedAt = first

        round.end(at: first.addingTimeInterval(60))

        XCTAssertEqual(round.endedAt, first)
    }

    func testCodableRoundTrip() throws {
        var round = Round(courseSelection: .test)
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        round.addStroke(stroke, toHoleIndex: 0)

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.id, round.id)
        XCTAssertEqual(decoded.date, round.date)
        XCTAssertEqual(decoded.displayHoleStrokes.count, 1)
        XCTAssertEqual(decoded.displayHoleStrokes[0].id, stroke.id)
        XCTAssertEqual(decoded, round)
    }

    func testCodableRoundTripEndedRound() throws {
        var round = Round(courseSelection: .test)
        round.lastSeq = 41
        round.endConfirmed = true
        round.end(at: Date(timeIntervalSince1970: 1_000_000))

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertFalse(decoded.isActive)
        XCTAssertEqual(decoded, round)
    }

    // MARK: - Display hole

    func testDisplayHoleStartsOnTheFirstHoleAtRoundDate() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let round = Round(date: date, courseSelection: .test)

        XCTAssertEqual(round.displayHoleNumber, 1)
        XCTAssertEqual(round.displayHole, DisplayHole(holeIndex: 0, changedAt: date))
    }

    func testSetDisplayHoleShowsTheHoleAndLeavesTheTimelineAlone() {
        var round = Round(courseSelection: .test)
        let when = round.date.addingTimeInterval(600)

        XCTAssertTrue(round.setDisplayHole(5, at: when))

        XCTAssertEqual(round.displayHole, DisplayHole(holeIndex: 5, changedAt: when))
        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0])
        XCTAssertEqual(round.holes.count, 1)
    }

    func testSetDisplayHoleIgnoresTheSameHoleAndHolesOffTheCourse() {
        var round = Round(courseSelection: .test)
        round.setDisplayHole(2, at: round.date.addingTimeInterval(600))

        XCTAssertFalse(round.setDisplayHole(2, at: round.date.addingTimeInterval(700)))
        XCTAssertFalse(round.setDisplayHole(-1, at: round.date.addingTimeInterval(700)))
        XCTAssertFalse(round.setDisplayHole(round.lastHoleIndex + 1, at: round.date.addingTimeInterval(700)))
        XCTAssertTrue(round.setDisplayHole(round.lastHoleIndex, at: round.date.addingTimeInterval(700)))
    }

    func testSetDisplayHoleTimedBeforeTheLastChangeIsPlacedJustAfterIt() {
        var round = Round(courseSelection: .test)
        round.setDisplayHole(2, at: round.date.addingTimeInterval(600))

        // The other device's clock runs a little ahead
        XCTAssertTrue(round.setDisplayHole(1, at: round.date.addingTimeInterval(599)))
        XCTAssertEqual(round.displayHoleIndex, 1)
        XCTAssertGreaterThan(round.displayHole.changedAt, round.date.addingTimeInterval(600))
    }

    func testMergeDisplayHoleTakesTheLaterChangeOnly() {
        var round = Round(courseSelection: .test)
        round.setDisplayHole(2, at: round.date.addingTimeInterval(600))

        XCTAssertFalse(round.mergeDisplayHole(DisplayHole(holeIndex: 4, changedAt: round.date.addingTimeInterval(500))))
        XCTAssertEqual(round.displayHoleIndex, 2)
        XCTAssertTrue(round.mergeDisplayHole(DisplayHole(holeIndex: 4, changedAt: round.date.addingTimeInterval(700))))
        XCTAssertEqual(round.displayHoleIndex, 4)
        XCTAssertFalse(round.mergeDisplayHole(round.displayHole))
    }

    func testMergeDisplayHoleAtTheSameTimeTakesTheHigherHole() {
        var round = Round(courseSelection: .test)
        let when = round.date.addingTimeInterval(600)
        round.setDisplayHole(2, at: when)

        XCTAssertFalse(round.mergeDisplayHole(DisplayHole(holeIndex: 1, changedAt: when)))
        XCTAssertTrue(round.mergeDisplayHole(DisplayHole(holeIndex: 3, changedAt: when)))
        XCTAssertEqual(round.displayHoleIndex, 3)
    }

    func testMergeDisplayHoleIgnoresAHoleOffTheCourse() {
        var round = Round(courseSelection: .test)

        XCTAssertFalse(round.mergeDisplayHole(DisplayHole(holeIndex: 18, changedAt: round.date.addingTimeInterval(600))))
    }

    func testDisplayHoleStrokes() {
        let stroke1 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        var round = Round(holes: [RoundHole(strokes: [stroke1]), RoundHole(strokes: [stroke2])], courseSelection: .test)
        round.setDisplayHole(1, at: round.date.addingTimeInterval(600))

        XCTAssertEqual(round.displayHoleStrokes.map(\.id), [stroke2.id])
        // A hole play has not reached has no strokes
        round.setDisplayHole(7, at: round.date.addingTimeInterval(700))
        XCTAssertTrue(round.displayHoleStrokes.isEmpty)
    }

    // MARK: - Hole timeline

    func testStartHoleAddsAStartAndAppendsHoles() {
        var round = Round(courseSelection: .test)
        round.addStroke(Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0)), toHoleIndex: 0)

        let changed = round.startHole(1, at: round.date.addingTimeInterval(600), source: .stroke)

        XCTAssertTrue(changed)
        XCTAssertEqual(round.holes.count, 2)
        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0, 1])
        XCTAssertEqual(round.holeTimeline.last?.source, .stroke)
        XCTAssertEqual(round.displayHoleIndex, 0) // the timeline does not move the display
    }

    func testStartHoleCanSkipAhead() {
        var round = Round(courseSelection: .test)

        round.startHole(6, at: round.date.addingTimeInterval(600), source: .stroke)

        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0, 6])
        XCTAssertEqual(round.holes.count, 7)
    }

    func testStartHoleIgnoresAHoleThatHasAStart() {
        var round = Round(courseSelection: .test)
        round.startHole(3, at: round.date.addingTimeInterval(600), source: .stroke)

        XCTAssertFalse(round.startHole(0, at: round.date.addingTimeInterval(1200), source: .stroke))
        XCTAssertFalse(round.startHole(3, at: round.date.addingTimeInterval(1200), source: .stroke))
        XCTAssertEqual(round.holeTimeline.count, 2)
    }

    func testStartHoleMustFitBetweenTheHolesAroundIt() {
        var round = Round(courseSelection: .test)
        round.startHole(3, at: round.date.addingTimeInterval(600), source: .stroke)

        // An earlier hole before hole 4's start fits in
        XCTAssertTrue(round.startHole(1, at: round.date.addingTimeInterval(300), source: .stroke))
        // An earlier hole after hole 4's start, or a later hole before it, does not
        XCTAssertFalse(round.startHole(2, at: round.date.addingTimeInterval(900), source: .stroke))
        XCTAssertFalse(round.startHole(5, at: round.date.addingTimeInterval(400), source: .stroke))
        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0, 1, 3])
        XCTAssertEqual(round.holeTimeline.map(\.startedAt), [0, 300, 600].map { round.date.addingTimeInterval($0) })
    }

    func testStartHoleDoesNotPassLastHole() {
        var round = Round(courseSelection: .test)

        XCTAssertFalse(round.startHole(Round.maxHoles, at: round.date.addingTimeInterval(600), source: .stroke))
        XCTAssertTrue(round.startHole(Round.maxHoles - 1, at: round.date.addingTimeInterval(600), source: .stroke))
        XCTAssertEqual(round.holes.count, Round.maxHoles)
    }

    func testStrokeHitStartsAHoleWithNoStart() {
        var round = Round(courseSelection: .test)

        XCTAssertTrue(round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(600)))

        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0, 2])
        XCTAssertEqual(round.holeTimeline[1].startedAt, round.date.addingTimeInterval(600))
        XCTAssertEqual(round.holeTimeline[1].source, .stroke)
    }

    func testLaterStrokeHitLeavesTheStartAlone() {
        var round = Round(courseSelection: .test)
        round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(600))

        XCTAssertFalse(round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(700)))
        XCTAssertEqual(round.holeTimeline[1].startedAt, round.date.addingTimeInterval(600))
    }

    func testEarlierStrokeHitMovesTheStartBack() {
        var round = Round(courseSelection: .test)
        round.holeTimeline.append(HoleStart(holeIndex: 2, startedAt: round.date.addingTimeInterval(600), source: .estimated))

        XCTAssertTrue(round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(500)))

        XCTAssertEqual(round.holeTimeline[1].startedAt, round.date.addingTimeInterval(500))
        XCTAssertEqual(round.holeTimeline[1].source, .stroke)
        XCTAssertEqual(round.holeTimeline[1].version, 1)
    }

    func testStrokeHitNeverMovesAStartTheUserSet() {
        var round = Round(courseSelection: .test)
        round.holeTimeline.append(HoleStart(holeIndex: 2, startedAt: round.date.addingTimeInterval(600), source: .userSet))

        XCTAssertFalse(round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(500)))
        XCTAssertEqual(round.holeTimeline[1].startedAt, round.date.addingTimeInterval(600))
    }

    func testStrokeHitDoesNotMoveAStartBeforeTheHoleBeforeIt() {
        var round = Round(courseSelection: .test)
        round.strokeHit(onHole: 1, at: round.date.addingTimeInterval(300))
        round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(600))

        XCTAssertFalse(round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(300)))
        XCTAssertFalse(round.strokeHit(onHole: 2, at: round.date.addingTimeInterval(200)))
        XCTAssertEqual(round.holeTimeline.map(\.startedAt), [0, 300, 600].map { round.date.addingTimeInterval($0) })
    }

    func testStrokeHitOnTheFirstHoleChangesNothing() {
        var round = Round(courseSelection: .test)

        XCTAssertFalse(round.strokeHit(onHole: 0, at: round.date.addingTimeInterval(-10)))
        XCTAssertFalse(round.strokeHit(onHole: 0, at: round.date.addingTimeInterval(10)))
        XCTAssertEqual(round.holeTimeline[0].startedAt, round.date)
    }

    func testHoleIndexAtUsesTimeline() {
        var round = Round(courseSelection: .test)
        round.startHole(1, at: round.date.addingTimeInterval(600), source: .stroke)
        round.startHole(2, at: round.date.addingTimeInterval(1200), source: .stroke)

        XCTAssertEqual(round.holeIndex(at: round.date.addingTimeInterval(-10)), 0)
        XCTAssertEqual(round.holeIndex(at: round.date.addingTimeInterval(599)), 0)
        XCTAssertEqual(round.holeIndex(at: round.date.addingTimeInterval(600)), 1)
        XCTAssertEqual(round.holeIndex(at: round.date.addingTimeInterval(5000)), 2)
    }

    func testPossibleHolesReachTheNextStart() {
        var round = Round(courseSelection: .test)
        round.startHole(3, at: round.date.addingTimeInterval(600), source: .stroke)

        // Holes 2 and 3 have no start yet, so a moment before hole 4 can be on holes 1 to 3
        XCTAssertEqual(round.possibleHoles(at: round.date.addingTimeInterval(-10)), 0...2)
        XCTAssertEqual(round.possibleHoles(at: round.date.addingTimeInterval(599)), 0...2)
        XCTAssertEqual(round.possibleHoles(at: round.date.addingTimeInterval(600)), 3...round.lastHoleIndex)
    }

    func testMergeTimelineReportsChange() {
        var round = Round(courseSelection: .test)
        var other = round
        other.startHole(4, at: round.date.addingTimeInterval(600), source: .stroke)

        XCTAssertTrue(round.mergeTimeline(other.holeTimeline))
        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0, 4])
        XCTAssertFalse(round.mergeTimeline(other.holeTimeline))
    }

    func testAllStrokes() {
        let stroke1 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = RoundHole(strokes: [stroke1])
        let hole2 = RoundHole(strokes: [stroke2])
        let round = Round(holes: [hole1, hole2], courseSelection: .test)

        XCTAssertEqual(round.allStrokes.count, 2)
    }

    func testHoleIndexContaining() {
        let stroke1 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let hole1 = RoundHole(strokes: [stroke1])
        let hole2 = RoundHole(strokes: [stroke2])
        let round = Round(holes: [hole1, hole2], courseSelection: .test)

        XCTAssertEqual(round.holeIndex(containing: stroke1.id), 0)
        XCTAssertEqual(round.holeIndex(containing: stroke2.id), 1)
        XCTAssertNil(round.holeIndex(containing: UUID()))
    }

    func testEndTrimsTrailingEmptyHoles() {
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        var round = Round(holes: [RoundHole(strokes: [stroke]), RoundHole(), RoundHole()], courseSelection: .test)

        round.end(at: Date())

        XCTAssertEqual(round.holes.count, 1)
        XCTAssertFalse(round.isActive)
    }

    func testEndPreservesNonEmptyHoles() {
        let stroke1 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        var round = Round(holes: [RoundHole(strokes: [stroke1]), RoundHole(strokes: [stroke2])], courseSelection: .test)

        round.end(at: Date())

        XCTAssertEqual(round.holes.count, 2)
    }

    func testStrokesSnapshotHoldsEveryHole() {
        let stroke1 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let stroke2 = Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        var round = Round(holes: [RoundHole(strokes: [stroke1]), RoundHole(strokes: [stroke2])], courseSelection: .test)
        round.strokesVersion = 7

        let snapshot = round.strokesSnapshot

        XCTAssertEqual(snapshot.roundID, round.id)
        XCTAssertEqual(snapshot.version, 7)
        XCTAssertEqual(snapshot.holes, [[stroke1], [stroke2]])
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

        XCTAssertEqual(round.course.name, "Test Course")
        XCTAssertEqual(round.courseSelection.selectedSubCourseIndices, [0])
    }

    func testDecodeWithoutCourseFails() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Round(courseSelection: .test))) as! [String: Any]
        json["courseSelection"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try JSONDecoder().decode(Round.self, from: data))
    }

    func testRoundCourseSelectionEncodeDecode() throws {
        let selection = makeCourseSelection()
        let round = Round(courseSelection: selection)

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.courseSelection, selection)
        XCTAssertEqual(decoded.course.name, "Test Course")
        XCTAssertEqual(decoded.courseSelection.orderedHoles.count, 2)
    }

    func testDisplayCourseHole() {
        let selection = makeCourseSelection()
        var round = Round(courseSelection: selection)

        XCTAssertEqual(round.displayCourseHole?.id, 1)
        XCTAssertEqual(round.displayCourseHole?.par, 4)

        round.setDisplayHole(1, at: round.date.addingTimeInterval(600))

        XCTAssertEqual(round.displayCourseHole?.id, 2)
        XCTAssertEqual(round.displayCourseHole?.par, 3)

        // The course's last hole is the last one that can be shown or started
        XCTAssertEqual(round.lastHoleIndex, 1)
        XCTAssertFalse(round.setDisplayHole(2, at: round.date.addingTimeInterval(1200)))
        XCTAssertFalse(round.startHole(2, at: round.date.addingTimeInterval(1200), source: .stroke))
        XCTAssertNil(round.courseHole(at: 2))
    }

    func testCodableRoundTripWithMultipleHoles() throws {
        var round = Round(courseSelection: .test)
        round.addStroke(Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0)), toHoleIndex: 0)
        round.startHole(1, at: round.date.addingTimeInterval(600), source: .stroke)
        round.addStroke(Stroke(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0)), toHoleIndex: 1)
        round.setDisplayHole(1, at: round.date.addingTimeInterval(700))

        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)

        XCTAssertEqual(decoded.holes.count, 2)
        XCTAssertEqual(decoded.holeTimeline, round.holeTimeline)
        XCTAssertEqual(decoded.displayHole, round.displayHole)
        XCTAssertEqual(decoded.holes[0].strokes.count, 1)
        XCTAssertEqual(decoded.holes[1].strokes.count, 1)
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

    // MARK: - Duplicate stroke detection

    func testAddStrokeToHoleIgnoresDuplicate() {
        var round = Round(courseSelection: .test)
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        round.addStroke(stroke, toHoleIndex: 0)
        round.addStroke(stroke, toHoleIndex: 0) // same UUID

        XCTAssertEqual(round.holes[0].strokes.count, 1)
    }

    func testAddStrokeToHoleIgnoresDuplicateAcrossHoles() {
        var round = Round(holes: [RoundHole(), RoundHole()], courseSelection: .test)
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        round.addStroke(stroke, toHoleIndex: 0)
        round.addStroke(stroke, toHoleIndex: 1) // same UUID, different hole

        XCTAssertEqual(round.holes[0].strokes.count, 1)
        XCTAssertEqual(round.holes[1].strokes.count, 0)
    }
}

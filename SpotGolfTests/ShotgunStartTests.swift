import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// A round that starts on any hole of the selected nines. See plans/2026-10-17-shotgun-start.md.
final class ShotgunStartTests: XCTestCase {

    private func selection(_ nines: [Int] = [0, 1], start: Int) -> CourseSelection {
        CourseSelection(course: CourseSelection.test.course, selectedSubCourseIndices: nines, startHoleIndex: start)
    }

    // MARK: - CourseSelection

    func testPlayOrderStartsAtTheStartingHoleAndWraps() {
        let shotgun = selection(start: 8)

        XCTAssertEqual(shotgun.orderedHoles.map(\.number), Array(9...18) + Array(1...8))
        XCTAssertEqual(shotgun.holeCount, 18)
        XCTAssertEqual(shotgun.startIndex, 8)
    }

    func testHoleNumbersAreInNineOrderBothWays() {
        let shotgun = selection(start: 8)

        XCTAssertEqual(shotgun.holeNumber(at: 0), 9)
        XCTAssertEqual(shotgun.holeNumber(at: 9), 18)
        XCTAssertEqual(shotgun.holeNumber(at: 10), 1)
        XCTAssertEqual(shotgun.holeNumber(at: 17), 8)
        XCTAssertEqual(shotgun.playIndex(ofHoleNumber: 9), 0)
        XCTAssertEqual(shotgun.playIndex(ofHoleNumber: 1), 10)
        for number in 1...18 {
            XCTAssertEqual(shotgun.holeNumber(at: shotgun.playIndex(ofHoleNumber: number)), number)
        }
    }

    func testOneNineWrapsAtNine() {
        let backOnly = selection([1], start: 4)

        XCTAssertEqual(backOnly.orderedHoles.map(\.number), [14, 15, 16, 17, 18, 10, 11, 12, 13])
        XCTAssertEqual(backOnly.holeNumber(at: 0), 5)
        XCTAssertEqual(backOnly.holeNumber(at: 8), 4)
    }

    func testHoleKeysStayWithTheirHoles() {
        let shotgun = selection(start: 8)

        XCTAssertEqual(shotgun.holeKey(at: 0)?.subCourse, "Front")
        XCTAssertEqual(shotgun.holeKey(at: 0)?.number, 9)
        XCTAssertEqual(shotgun.holeKey(at: 10)?.number, 1)
        XCTAssertEqual(shotgun.holeIndex(subCourse: "Front", number: 1), 10)
        XCTAssertEqual(shotgun.holeIndex(subCourse: "Back", number: 18), 9)
    }

    func testHoleOneAndOutOfRangeStartsPlayInNineOrder() {
        for start in [0, -1, 18, 40] {
            let plain = selection(start: start)
            XCTAssertEqual(plain.startIndex, 0)
            XCTAssertEqual(plain.orderedHoles.map(\.number), Array(1...18))
            XCTAssertEqual(plain.holeNumber(at: 4), 5)
        }
    }

    func testHoleNumbersPastTheLastHoleCountOn() {
        let shotgun = selection(start: 8)

        XCTAssertEqual(shotgun.holeNumber(at: 18), 19)
        XCTAssertEqual(shotgun.playIndex(ofHoleNumber: 19), 18)
    }

    func testStartingHoleSurvivesCodingTrimmingAndPickingATee() throws {
        let shotgun = selection(start: 8)

        let decoded = try JSONDecoder().decode(CourseSelection.self, from: JSONEncoder().encode(shotgun))
        XCTAssertEqual(decoded, shotgun)
        XCTAssertEqual(decoded.startIndex, 8)
        XCTAssertEqual(shotgun.trimmed.startIndex, 8)
        XCTAssertEqual(shotgun.with(tee: "Blue").startIndex, 8)
        XCTAssertEqual(shotgun.with(tee: "Blue").teeName, "Blue")
    }

    func testSelectionsWithoutAStartingHoleCodeAsBefore() throws {
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(CourseSelection.test), encoding: .utf8))
        XCTAssertFalse(json.contains("startHoleIndex"))

        // A saved selection from before shotgun starts
        let decoded = try JSONDecoder().decode(CourseSelection.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.startIndex, 0)
        XCTAssertEqual(decoded, CourseSelection.test)
    }

    // MARK: - Round

    func testDisplayHoleNumberFollowsTheStartingHole() {
        let round = Round(courseSelection: selection(start: 8))

        XCTAssertEqual(round.displayHoleNumber, 9)
        XCTAssertTrue(round.setDisplayHole(10, at: round.date.addingTimeInterval(600)))
        XCTAssertEqual(round.displayHoleNumber, 1)
        XCTAssertEqual(round.holeNumber(at: round.lastHoleIndex), 8)
    }

    func testTimelineRunsFromTheEighteenthToTheFirst() {
        let round = Round(courseSelection: selection(start: 8))

        // Hole 18 is index 9, hole 1 index 10, hole 8 the last
        XCTAssertTrue(round.startHole(9, at: round.date.addingTimeInterval(9 * 900)))
        XCTAssertTrue(round.startHole(10, at: round.date.addingTimeInterval(10 * 900)))
        XCTAssertTrue(round.startHole(17, at: round.date.addingTimeInterval(17 * 900)))
        XCTAssertEqual(round.holeTimeline.map { round.holeNumber(at: $0.holeIndex) }, [9, 18, 1, 8])
        XCTAssertEqual(round.holeIndex(at: round.date.addingTimeInterval(10 * 900 + 60)), 10)
    }

    // MARK: - Export and import

    func testExportUsesHoleNumbersAndImportPutsStrokesBack() throws {
        let shotgun = selection(start: 8)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let round = Round(date: start, courseSelection: shotgun)
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.0, longitude: -105.0))
        round.addStroke(stroke, toHoleIndex: 10)

        let csv = TrackExporter.csv(round: round, points: [TrackPoint(timestamp: start, latitude: 39.0, longitude: -105.0,
                                                                         altitude: nil)], swings: [])
        XCTAssertTrue(csv.contains("stroke,,39.0,-105.0,,,,1,1,"), csv)

        let imported = try TrackImporter.round(from: TrackImporter.read(csv), courseSelection: shotgun).round
        XCTAssertEqual(imported.hole(at: 10).strokes.count, 1)
        XCTAssertEqual(imported.hole(at: 0).strokes.count, 0)
    }
}

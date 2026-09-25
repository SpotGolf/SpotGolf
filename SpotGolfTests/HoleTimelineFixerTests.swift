import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

final class HoleTimelineFixerTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Five holes whose tees are about 1 km apart, due north of each other.
    private let selection: CourseSelection = {
        let tees = (0..<5).map { index -> Feature in
            let lat = HoleTimelineFixerTests.teeLatitude(index)
            let d = 0.0001 // about 11 m
            return Feature(id: 100 + index, type: .tee, polygon: [
                Coordinate(latitude: lat - d, longitude: -105 - d),
                Coordinate(latitude: lat - d, longitude: -105 + d),
                Coordinate(latitude: lat + d, longitude: -105 + d),
                Coordinate(latitude: lat + d, longitude: -105 - d)
            ])
        }
        let holes = (0..<5).map { Hole(number: $0 + 1, par: 4, tees: ["Blue": 100 + $0]) }
        return CourseSelection(
            course: Course(name: "Tee Course",
                           location: CourseLocation(address: "", city: "", state: "", country: "US",
                                                    coordinate: Coordinate(latitude: 40, longitude: -105)),
                           features: tees,
                           subCourses: [SubCourse(name: "Front", holes: holes)]),
            selectedSubCourseIndices: [0]
        )
    }()

    private static func teeLatitude(_ hole: Int) -> Double { 40 + Double(hole) * 0.01 }

    private func time(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// A fix on hole `hole`'s tee.
    private func onTee(_ hole: Int, _ minutes: Double) -> TrackPoint {
        TrackPoint(timestamp: time(minutes), latitude: Self.teeLatitude(hole), longitude: -105, altitude: nil)
    }

    /// A fix far from every tee.
    private func away(_ minutes: Double) -> TrackPoint {
        TrackPoint(timestamp: time(minutes), latitude: 40.005, longitude: -105.01, altitude: nil)
    }

    private func round(_ timeline: [(hole: Int, minutes: Double, source: HoleStartSource)],
                       marks: [(hole: Int, minutes: Double)] = []) -> Round {
        var round = Round(date: start, courseSelection: selection)
        round.holeTimeline = timeline.map { HoleStart(holeIndex: $0.hole, startedAt: time($0.minutes), source: $0.source) }
        for mark in marks {
            round.addMark(BallMark(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -105), timestamp: time(mark.minutes)),
                          toHoleIndex: mark.hole)
        }
        return round
    }

    private func starts(_ entries: [HoleStart]) -> [Int: Date] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.holeIndex, $0.startedAt) })
    }

    // MARK: - Skipped holes

    func testJumpFillsInSkippedHolesFromTheirTees() {
        // Stuck on hole 1, the user taps "Play hole 4" at 40 minutes
        let round = round([(0, 0, .roundStart), (3, 40, .playHole)])
        let points = [away(5), onTee(1, 12), away(18), onTee(2, 25), away(30), onTee(3, 39)]

        let fixed = HoleTimelineFixer.fixed(round, points: points, swings: [])

        XCTAssertEqual(fixed.map(\.holeIndex), [0, 1, 2, 3])
        XCTAssertEqual(fixed[1].startedAt, time(12))
        XCTAssertEqual(fixed[1].source, .estimated)
        XCTAssertEqual(fixed[2].startedAt, time(25))
        XCTAssertEqual(fixed[3].startedAt, time(40))
    }

    func testSwingOnTheTeeIsUsedBeforeTheFirstFixThere() {
        let round = round([(0, 0, .roundStart), (2, 40, .playHole)])
        // Walked past the tee at 10, teed off at 12
        let points = [onTee(1, 10), away(11), onTee(1, 12), away(20)]
        let swings = [Swing(timestamp: time(12), peakG: 14)]

        let fixed = HoleTimelineFixer.fixed(round, points: points, swings: swings)

        XCTAssertEqual(starts(fixed)[1], time(12))
    }

    func testSwingAwayFromTheTeeIsNotUsed() {
        let round = round([(0, 0, .roundStart), (2, 40, .playHole)])
        let points = [away(5), onTee(1, 12)]
        let swings = [Swing(timestamp: time(5), peakG: 14)]

        XCTAssertEqual(starts(HoleTimelineFixer.fixed(round, points: points, swings: swings))[1], time(12))
    }

    func testHoleWithNoTeeFixGetsNoEntry() {
        let round = round([(0, 0, .roundStart), (3, 40, .playHole)])
        let points = [onTee(1, 12), away(25)]

        let fixed = HoleTimelineFixer.fixed(round, points: points, swings: [])

        XCTAssertEqual(fixed.map(\.holeIndex), [0, 1, 3])
    }

    func testTeeFixOutsideTheGapIsNotUsed() {
        let round = round([(0, 0, .roundStart), (1, 10, .autoAdvance), (3, 40, .playHole)])
        // Hole 3's tee was only reached after the jump
        let points = [onTee(2, 45)]

        XCTAssertEqual(HoleTimelineFixer.fixed(round, points: points, swings: []).map(\.holeIndex), [0, 1, 3])
    }

    // MARK: - Marks

    func testEarlyAutoAdvanceIsMovedAfterLastMarkOnPreviousHole() throws {
        // Auto-advance fired at 10 while the player still hit from hole 1 at 14
        let round = round([(0, 0, .roundStart), (1, 10, .autoAdvance)],
                          marks: [(0, 5), (0, 14), (1, 20)])
        let points = [onTee(1, 10), away(14), onTee(1, 16), away(20)]

        let fixed = HoleTimelineFixer.fixed(round, points: points, swings: [])

        let entry = try XCTUnwrap(fixed.first { $0.holeIndex == 1 })
        XCTAssertEqual(entry.startedAt, time(16))
        XCTAssertEqual(entry.source, .corrected)
        XCTAssertEqual(entry.version, 1)
    }

    func testLatePlayTapIsMovedToTheTeeBeforeTheFirstMark() {
        // The player teed off at 12 and marked at 20, then tapped "Play this hole" at 30
        let round = round([(0, 0, .roundStart), (1, 30, .playHole)],
                          marks: [(0, 2), (0, 8), (1, 20)])
        let points = [away(9), onTee(1, 12), away(20)]

        XCTAssertEqual(starts(HoleTimelineFixer.fixed(round, points: points, swings: []))[1], time(12))
    }

    func testTimeSetByTheUserIsNotMoved() {
        let round = round([(0, 0, .roundStart), (1, 30, .userSet)],
                          marks: [(0, 2), (0, 8), (1, 20)])
        let points = [away(9), onTee(1, 12), away(20)]

        XCTAssertEqual(starts(HoleTimelineFixer.fixed(round, points: points, swings: []))[1], time(30))
    }

    func testWithoutTeeFixTheFirstMarkIsTheStart() {
        let round = round([(0, 0, .roundStart), (1, 30, .playHole)],
                          marks: [(0, 8), (1, 20)])

        XCTAssertEqual(starts(HoleTimelineFixer.fixed(round, points: [away(10)], swings: []))[1], time(20))
    }

    func testEntryInsideMarkWindowIsLeftAlone() {
        let round = round([(0, 0, .roundStart), (1, 10, .autoAdvance)],
                          marks: [(0, 5), (1, 20)])

        XCTAssertEqual(HoleTimelineFixer.fixed(round, points: [onTee(1, 12)], swings: []), round.holeTimeline)
    }

    func testHoleWithoutMarksIsNotCorrectedByTheLateRule() {
        let round = round([(0, 0, .roundStart), (1, 30, .playHole)], marks: [(0, 8)])

        XCTAssertEqual(HoleTimelineFixer.fixed(round, points: [onTee(1, 12)], swings: []), round.holeTimeline)
    }

    func testFixingAgainChangesNothing() {
        var round = round([(0, 0, .roundStart), (1, 10, .autoAdvance), (4, 60, .playHole)],
                          marks: [(0, 5), (0, 14), (1, 20)])
        let points = [onTee(1, 16), onTee(2, 30), onTee(3, 45)]

        round.holeTimeline = HoleTimelineFixer.fixed(round, points: points, swings: [])

        XCTAssertEqual(HoleTimelineFixer.fixed(round, points: points, swings: []), round.holeTimeline)
    }

    func testDeletingTheMarkKeepsTheCorrection() {
        var round = round([(0, 0, .roundStart), (1, 10, .autoAdvance)], marks: [(0, 14), (1, 20)])
        let points = [onTee(1, 16)]
        round.holeTimeline = HoleTimelineFixer.fixed(round, points: points, swings: [])

        round.holes[0].marks.removeAll()

        XCTAssertEqual(starts(HoleTimelineFixer.fixed(round, points: points, swings: []))[1], time(16))
    }

    // MARK: - Distance

    func testDistanceIsZeroInsideAndMetersOutside() {
        let tee = HoleTimelineFixer.teePolygons(hole: 1, round: round([(0, 0, .roundStart)]))[0]

        XCTAssertEqual(HoleTimelineFixer.distance(from: Coordinate(latitude: Self.teeLatitude(1), longitude: -105), to: tee), 0)
        // 0.0003° north of the center is about 22 m from the tee's north edge
        let outside = HoleTimelineFixer.distance(from: Coordinate(latitude: Self.teeLatitude(1) + 0.0003, longitude: -105), to: tee)
        XCTAssertEqual(outside, 22, accuracy: 2)
    }
}

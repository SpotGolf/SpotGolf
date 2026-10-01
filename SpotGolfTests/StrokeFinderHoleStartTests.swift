import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// `StrokeFinder.holeStarts` on `PathCourse`: holes start when the player leaves the previous green.
final class StrokeFinderHoleStartTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A GPS path with one fix per second, in meters from hole 1's tee.
    private struct Path {
        let start: Date
        var points: [TrackPoint] = []
        var north: Double = 0
        var east: Double = 0

        var now: Date { start.addingTimeInterval(TimeInterval(points.count)) }

        mutating func stand(_ seconds: Int) {
            for _ in 0..<seconds { addFix() }
        }

        /// Walks in a straight line at 2 m/s.
        mutating func walk(north toNorth: Double, east toEast: Double) {
            let distance = ((toNorth - north) * (toNorth - north) + (toEast - east) * (toEast - east)).squareRoot()
            let steps = max(Int((distance / 2).rounded(.up)), 1)
            let (fromNorth, fromEast) = (north, east)
            for step in 1...steps {
                let fraction = Double(step) / Double(steps)
                north = fromNorth + (toNorth - fromNorth) * fraction
                east = fromEast + (toEast - fromEast) * fraction
                addFix()
            }
        }

        func swing() -> StrokeSuggestion {
            .swing(at: now, peakG: 20)
        }

        private mutating func addFix() {
            let point = PathCourse.coordinate(north: north, east: east)
            points.append(TrackPoint(timestamp: now, latitude: point.latitude, longitude: point.longitude, altitude: nil))
        }
    }

    private func round(_ timeline: [(hole: Int, at: Date, source: HoleStartSource)] = []) -> Round {
        var round = Round(date: start, courseSelection: PathCourse.selection)
        round.holeTimeline += timeline.map { HoleStart(holeIndex: $0.hole, startedAt: $0.at, source: $0.source) }
        return round
    }

    /// Hole 1 from tee to green, then the walk to hole 2's tee. Returns the time the player left green 1.
    private func playHoleOneAndWalkToTeeTwo(_ path: inout Path) -> Date {
        path.stand(30)
        path.walk(north: 300, east: 0)
        path.stand(60)
        // Green 1 is 30 m wide: 10 m past its edge is 25 m east of its center
        path.walk(north: 300, east: 24)
        let leftGreen = path.now
        path.walk(north: 300, east: 60)
        path.stand(30)
        return leftGreen
    }

    func testLeavingTheGreenStartsTheNextHole() {
        var path = Path(start: start)
        let leftGreen = playHoleOneAndWalkToTeeTwo(&path)

        let starts = StrokeFinder.holeStarts(round: round(), points: path.points, swings: [])

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1])
        XCTAssertEqual(starts[1].startedAt, leftGreen)
        XCTAssertEqual(starts[1].source, .estimated)
    }

    func testOverhitApproachAndWalkBackEndsTheHoleAtTheLastGreenVisit() {
        var path = Path(start: start)
        path.stand(30)
        path.walk(north: 300, east: 0)
        path.stand(20)
        // Over the green, 15 m short of hole 2's tee box, then back to the green to putt out
        path.walk(north: 300, east: 40)
        path.stand(20)
        path.walk(north: 300, east: 0)
        path.stand(60)
        path.walk(north: 300, east: 24)
        let leftGreen = path.now
        path.walk(north: 300, east: 60)
        path.stand(30)

        let starts = StrokeFinder.holeStarts(round: round(), points: path.points, swings: [])

        XCTAssertEqual(starts[1].startedAt, leftGreen)
    }

    func testTeePassedBeforeReachingTheGreenDoesNotStartTheHole() {
        var path = Path(start: start)
        path.stand(30)
        // Wanders past hole 2's tee first
        path.walk(north: 300, east: 60)
        path.stand(20)
        path.walk(north: 300, east: 0)
        path.stand(60)
        path.walk(north: 300, east: 24)
        let leftGreen = path.now
        path.walk(north: 300, east: 60)
        path.stand(30)

        let starts = StrokeFinder.holeStarts(round: round(), points: path.points, swings: [])

        XCTAssertEqual(starts[1].startedAt, leftGreen)
    }

    func testWithoutAGreenVisitTheHoleStartsAtTheTee() {
        var path = Path(start: start)
        path.stand(30)
        // Picked up the ball short of the green and went to the next tee
        path.walk(north: 200, east: 0)
        path.walk(north: 300, east: 55)
        let arrival = path.now
        path.stand(30)

        let starts = StrokeFinder.holeStarts(round: round(), points: path.points, swings: [])

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1])
        XCTAssertEqual(starts[1].startedAt.timeIntervalSince(arrival), 0, accuracy: 20)
    }

    func testLateWatchEntryIsMovedToWhenThePlayerLeftTheGreen() {
        var path = Path(start: start)
        let leftGreen = playHoleOneAndWalkToTeeTwo(&path)
        let late = path.now

        let starts = StrokeFinder.holeStarts(round: round([(1, late, .autoAdvance)]), points: path.points, swings: [])

        XCTAssertEqual(starts[1].startedAt, leftGreen)
        XCTAssertEqual(starts[1].source, .corrected)
        XCTAssertEqual(starts[1].version, 1)
    }

    func testTimeSetByTheUserIsNotMoved() {
        var path = Path(start: start)
        _ = playHoleOneAndWalkToTeeTwo(&path)
        let set = path.now

        let starts = StrokeFinder.holeStarts(round: round([(1, set, .userSet)]), points: path.points, swings: [])

        XCTAssertEqual(starts[1].startedAt, set)
        XCTAssertEqual(starts[1].source, .userSet)
    }

    func testSkippedHoleIsFilledIn() {
        var path = Path(start: start)
        _ = playHoleOneAndWalkToTeeTwo(&path)
        path.walk(north: 300, east: 360)
        path.stand(60)
        path.walk(north: 300, east: 400)
        path.walk(north: 300, east: 420)
        path.stand(30)
        let jump = path.now

        let starts = StrokeFinder.holeStarts(round: round([(2, jump, .playHole)]), points: path.points, swings: [])

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1, 2])
        XCTAssertEqual(starts[1].source, .estimated)
        XCTAssertLessThan(starts[2].startedAt, jump)
    }

    func testTeeSwingIsUsedWhenThePreviousHoleHasNoGreen() {
        // Hole 1 has no green in this course, so the hole starts at the tee shot
        var course = PathCourse.selection
        let greenID = 200
        course = CourseSelection(
            course: Course(name: course.course.name, location: course.course.location,
                           features: course.course.features.filter { $0.id != greenID },
                           subCourses: course.course.subCourses),
            selectedSubCourseIndices: course.selectedSubCourseIndices)
        var path = Path(start: start)
        path.stand(30)
        path.walk(north: 300, east: 0)
        path.stand(60)
        path.walk(north: 300, east: 60)
        path.stand(20)
        let teeShot = path.swing()
        path.stand(10)

        var round = Round(date: start, courseSelection: course)
        round.holeTimeline = [HoleStart(holeIndex: 0, startedAt: start, source: .roundStart)]
        let starts = StrokeFinder.holeStarts(round: round, points: path.points, swings: [teeShot])

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1])
        XCTAssertEqual(starts[1].startedAt, teeShot.timestamp)
    }

    func testCourseWithoutTeesChangesNothing() {
        var path = Path(start: start)
        _ = playHoleOneAndWalkToTeeTwo(&path)
        let round = Round(date: start, courseSelection: .test)

        XCTAssertEqual(StrokeFinder.holeStarts(round: round, points: path.points, swings: []), round.holeTimeline)
    }

    func testRunningAgainChangesNothing() {
        var path = Path(start: start)
        _ = playHoleOneAndWalkToTeeTwo(&path)
        var round = round([(1, path.now, .autoAdvance)])

        round.holeTimeline = StrokeFinder.holeStarts(round: round, points: path.points, swings: [])

        XCTAssertEqual(StrokeFinder.holeStarts(round: round, points: path.points, swings: []), round.holeTimeline)
    }

    func testDistanceIsZeroInsideAndToTheNearestEdgeOutside() {
        let square = PathCourse.square(north: 0, east: 0, half: 10)

        XCTAssertEqual(StrokeFinder.distance(from: PathCourse.coordinate(north: 0, east: 0), to: square), 0)
        // 5 m out from the middle of an edge, far from any corner
        XCTAssertEqual(StrokeFinder.distance(from: PathCourse.coordinate(north: 0, east: 15), to: square), 5, accuracy: 0.1)
    }
}

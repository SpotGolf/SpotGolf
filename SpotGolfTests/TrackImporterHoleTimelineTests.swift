import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// `TrackImporter.holeTimeline` on `PathCourse`: holes start when the player leaves the previous green.
final class TrackImporterHoleTimelineTests: XCTestCase {

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

        private mutating func addFix() {
            let point = PathCourse.coordinate(north: north, east: east)
            points.append(TrackPoint(timestamp: now, latitude: point.latitude, longitude: point.longitude, altitude: nil))
        }
    }

    private func timeline(_ path: Path, course: CourseSelection = PathCourse.selection) -> [HoleStart] {
        TrackImporter.holeTimeline(of: Round(date: start, courseSelection: course), points: path.points)
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

        let starts = timeline(path)

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1])
        XCTAssertEqual(starts[0].source, .roundStart)
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

        XCTAssertEqual(timeline(path)[1].startedAt, leftGreen)
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

        XCTAssertEqual(timeline(path)[1].startedAt, leftGreen)
    }

    func testWithoutAGreenVisitTheHoleStartsAtTheTee() {
        var path = Path(start: start)
        path.stand(30)
        // Picked up the ball short of the green and went to the next tee
        path.walk(north: 200, east: 0)
        path.walk(north: 300, east: 55)
        let arrival = path.now
        path.stand(30)

        let starts = timeline(path)

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1])
        XCTAssertEqual(starts[1].startedAt.timeIntervalSince(arrival), 0, accuracy: 20)
    }

    /// Coal Creek, 2026-10-02: the walk from the 8th green to the 9th tee crossed the 18th tee.
    func testLaterTeePassedOnTheWayToTheNextTeeIsNotPlayed() {
        var path = Path(start: start)
        path.stand(30)
        path.walk(north: 300, east: 0)
        path.stand(60)
        path.walk(north: 300, east: 24)
        let leftGreen = path.now
        // Around hole 2's tee, across hole 3's tee, and back to hole 2's tee
        path.walk(north: 300, east: 30)
        path.walk(north: 250, east: 30)
        path.walk(north: 250, east: 420)
        path.walk(north: 300, east: 420)
        path.stand(10)
        path.walk(north: 250, east: 420)
        path.walk(north: 250, east: 60)
        path.walk(north: 300, east: 60)
        path.stand(30)

        let starts = timeline(path)

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1])
        XCTAssertEqual(starts[1].startedAt, leftGreen)
    }

    func testEveryHoleIsTakenInOrder() {
        var path = Path(start: start)
        _ = playHoleOneAndWalkToTeeTwo(&path)
        path.walk(north: 300, east: 360)
        path.stand(60)
        path.walk(north: 300, east: 384)
        let leftGreenTwo = path.now
        path.walk(north: 300, east: 420)
        path.stand(30)

        let starts = timeline(path)

        XCTAssertEqual(starts.map(\.holeIndex), [0, 1, 2])
        XCTAssertEqual(starts[2].startedAt, leftGreenTwo)
    }

    func testCourseWithoutTeesHasOnlyTheRoundStart() {
        var path = Path(start: start)
        _ = playHoleOneAndWalkToTeeTwo(&path)

        XCTAssertEqual(timeline(path, course: .test).map(\.holeIndex), [0])
    }

    func testImportedRoundGetsItsTimelineFromTheGPS() throws {
        var path = Path(start: start)
        let leftGreen = playHoleOneAndWalkToTeeTwo(&path)
        let export = TrackImporter.Export(points: path.points)

        let (round, _) = try TrackImporter.round(from: export, courseSelection: PathCourse.selection)

        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0, 1])
        XCTAssertEqual(round.holeTimeline[1].startedAt, leftGreen)
    }
}

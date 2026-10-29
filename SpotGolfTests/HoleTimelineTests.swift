import XCTest
@testable import SpotGolf

final class HoleTimelineTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// 18 holes, with a start `minutes` after `start` for each hole given and none for the rest.
    private func starts(_ minutes: [Int: Double]) -> [Date?] {
        (0..<18).map { hole in minutes[hole].map { start.addingTimeInterval($0 * 60) } }
    }

    /// 18 holes, with a last stroke `minutes` after `start` for each hole given and none for the rest.
    private func lastStrokes(_ minutes: [Int: Double]) -> [Date?] {
        starts(minutes)
    }

    func testHoleAtTime() {
        let starts = starts([0: 0, 1: 10, 4: 30])

        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(-60), in: starts), 0)
        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(9 * 60), in: starts), 0)
        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(10 * 60), in: starts), 1)
        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(45 * 60), in: starts), 4)
    }

    func testBeforeTheFirstStartIsTheFirstHoleWithAStart() {
        let starts = starts([2: 20])

        XCTAssertEqual(HoleTimeline.holeIndex(at: start, in: starts), 2)
        XCTAssertEqual(HoleTimeline.holeIndex(at: start, in: []), 0)
    }

    func testPossibleHolesRunToTheNextStart() {
        let starts = starts([0: 0, 1: 10, 4: 40])
        let lastStrokes = lastStrokes([0: 9, 1: 39])

        // Holes 2 and 3 have no start, so from hole 1's start to hole 4's a moment can be on 1, 2 or 3
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(-60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 0...0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(5 * 60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 0...0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(10 * 60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 1...3)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(45 * 60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 4...17)
    }

    func testAHoleWithNoStartReadsAsTheHoleBefore() {
        // Hole 1 has no start, so its GPS reads as hole 0 until hole 2's start
        let starts = starts([0: 0, 2: 20])

        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(15 * 60), in: starts), 0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(15 * 60), in: starts,
                                                  lastStrokes: lastStrokes([0: 18]), lastHoleIndex: 17), 0...1)
    }

    func testAMomentAfterTheLastStrokeCanBeOnTheNextHole() {
        // Hole 1's second shot, at 20, was turned into a stroke before its tee shot at 15
        let starts = starts([0: 0, 1: 20, 2: 40])
        let lastStrokes = lastStrokes([0: 12, 1: 30])

        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(11 * 60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 0...0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(15 * 60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 0...1)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(25 * 60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 1...1)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(35 * 60), in: starts, lastStrokes: lastStrokes, lastHoleIndex: 17), 1...2)
    }

    func testAMomentOnAHoleWithNoStrokesCanBeOnTheNextHole() {
        let starts = starts([0: 0, 1: 20])

        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(5 * 60), in: starts, lastStrokes: lastStrokes([:]), lastHoleIndex: 17), 0...1)
        // The last hole has no next hole
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(25 * 60), in: self.starts([0: 0, 17: 20]),
                                                  lastStrokes: lastStrokes([:]), lastHoleIndex: 17), 17...17)
    }

    func testFitsBetweenTheHolesAroundIt() {
        let starts = starts([0: 0, 2: 20, 5: 50])

        XCTAssertTrue(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(30 * 60), in: starts))
        XCTAssertFalse(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(10 * 60), in: starts))
        XCTAssertFalse(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(60 * 60), in: starts))
        XCTAssertFalse(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(20 * 60), in: starts))
        // Its own start does not count
        XCTAssertTrue(HoleTimeline.fits(holeIndex: 2, at: start.addingTimeInterval(5 * 60), in: starts))
    }
}

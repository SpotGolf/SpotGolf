import XCTest
@testable import SpotGolf

final class HoleTimelineTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// 18 holes, with a start `minutes` after `start` for each hole given and none for the rest.
    private func starts(_ minutes: [Int: Double]) -> [Date?] {
        (0..<18).map { hole in minutes[hole].map { start.addingTimeInterval($0 * 60) } }
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

        // Holes 2 and 3 have no start, so from hole 1's start to hole 4's a moment can be on 1, 2 or 3
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(-60), in: starts, lastHoleIndex: 17), 0...0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(5 * 60), in: starts, lastHoleIndex: 17), 0...0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(10 * 60), in: starts, lastHoleIndex: 17), 1...3)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(45 * 60), in: starts, lastHoleIndex: 17), 4...17)
    }

    func testAHoleWithNoStartReadsAsTheHoleBefore() {
        // Hole 1 has no start, so its GPS reads as hole 0 until hole 2's start
        let starts = starts([0: 0, 2: 20])

        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(15 * 60), in: starts), 0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(15 * 60), in: starts, lastHoleIndex: 17), 0...1)
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

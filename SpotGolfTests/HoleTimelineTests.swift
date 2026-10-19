import XCTest
@testable import SpotGolf

final class HoleTimelineTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ hole: Int, _ minutes: Double, id: UUID = UUID(), version: Int = 0) -> HoleStart {
        HoleStart(id: id, holeIndex: hole, startedAt: start.addingTimeInterval(minutes * 60), version: version)
    }

    private func cleared(_ hole: Int, id: UUID = UUID(), version: Int = 1) -> HoleStart {
        HoleStart(id: id, holeIndex: hole, startedAt: nil, version: version)
    }

    func testMergeIsUnionSortedByTime() {
        let a = [entry(0, 0), entry(2, 20)]
        let b = [entry(1, 10)]

        XCTAssertEqual(HoleTimeline.merge(a, b).map(\.holeIndex), [0, 1, 2])
    }

    func testMergeOfSameEntryKeepsOneCopy() {
        let shared = entry(1, 10)
        XCTAssertEqual(HoleTimeline.merge([entry(0, 0), shared], [shared]).count, 2)
    }

    func testHigherVersionWins() {
        let id = UUID()
        let original = entry(1, 10, id: id)
        let corrected = entry(1, 8, id: id, version: 1)

        XCTAssertEqual(HoleTimeline.merge([original], [corrected]), [corrected])
        XCTAssertEqual(HoleTimeline.merge([corrected], [original]), [corrected])
    }

    func testLowerHoleAfterHigherIsDropped() {
        // The phone jumps 3→7 at 10:05; the watch, not yet told, advances 3→4 at 10:06
        let phone = [entry(3, 0), entry(7, 5)]
        let watch = [entry(3, 0), entry(4, 6)]

        let merged = HoleTimeline.merge(phone, watch)

        XCTAssertEqual(merged.map(\.holeIndex), [3, 7])
        XCTAssertEqual(HoleTimeline.merge(watch, phone), merged)
    }

    func testMergeIsTheSameEitherWay() {
        let a = [entry(0, 0), entry(1, 10), entry(3, 30)]
        let b = [entry(0, 0), entry(2, 20), entry(2, 25)]

        XCTAssertEqual(HoleTimeline.merge(a, b), HoleTimeline.merge(b, a))
    }

    func testHoleAtTime() {
        let entries = [entry(0, 0), entry(1, 10), entry(4, 30)]

        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(-60), in: entries), 0)
        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(9 * 60), in: entries), 0)
        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(10 * 60), in: entries), 1)
        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(45 * 60), in: entries), 4)
    }

    func testPossibleHolesRunToTheNextStart() {
        let entries = [entry(0, 0), entry(1, 10), entry(4, 40)]

        // Holes 3 and 4 have no start, so from hole 2's start to hole 5's a moment can be on 2, 3 or 4
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(-60), in: entries, lastHoleIndex: 17), 0...0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(5 * 60), in: entries, lastHoleIndex: 17), 0...0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(10 * 60), in: entries, lastHoleIndex: 17), 1...3)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(45 * 60), in: entries, lastHoleIndex: 17), 4...17)
    }

    func testClearedStartWinsOverTheOlderCopy() {
        let id = UUID()
        let started = entry(2, 20, id: id)
        let clearedCopy = cleared(2, id: id)

        XCTAssertEqual(HoleTimeline.merge([entry(0, 0), started], [clearedCopy]).last, clearedCopy)
        XCTAssertEqual(HoleTimeline.merge([clearedCopy], [entry(0, 0), started]).last, clearedCopy)
    }

    func testClearedEntriesComeLastByHole() {
        let entries = [cleared(5), entry(0, 0), cleared(2), entry(3, 30)]

        let normalized = HoleTimeline.normalized(entries)

        XCTAssertEqual(normalized.map(\.holeIndex), [0, 3, 2, 5])
        XCTAssertEqual(normalized.map { $0.startedAt == nil }, [false, false, true, true])
    }

    func testClearedEntriesHaveNoStart() {
        // Hole 1 lost its start, so its GPS reads as hole 0 again until hole 2's start
        let entries = HoleTimeline.normalized([entry(0, 0), cleared(1), entry(2, 20)])

        XCTAssertEqual(HoleTimeline.holeIndex(at: start.addingTimeInterval(15 * 60), in: entries), 0)
        XCTAssertEqual(HoleTimeline.possibleHoles(at: start.addingTimeInterval(15 * 60), in: entries, lastHoleIndex: 17), 0...1)
    }

    func testFitsBetweenTheHolesAroundIt() {
        let entries = [entry(0, 0), entry(2, 20), cleared(3), entry(5, 50)]

        XCTAssertTrue(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(30 * 60), in: entries))
        XCTAssertFalse(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(10 * 60), in: entries))
        XCTAssertFalse(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(60 * 60), in: entries))
        XCTAssertFalse(HoleTimeline.fits(holeIndex: 3, at: start.addingTimeInterval(20 * 60), in: entries))
        // Its own start does not count
        XCTAssertTrue(HoleTimeline.fits(holeIndex: 2, at: start.addingTimeInterval(5 * 60), in: entries))
    }
}

import XCTest
@testable import SpotGolf

final class HoleTimelineTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ hole: Int, _ minutes: Double, id: UUID = UUID(), version: Int = 0,
                       source: HoleStartSource = .autoAdvance) -> HoleStart {
        HoleStart(id: id, holeIndex: hole, startedAt: start.addingTimeInterval(minutes * 60), source: source, version: version)
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
        let corrected = entry(1, 8, id: id, version: 1, source: .corrected)

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
}

import SwiftData
import XCTest
@testable import SpotGolf

@MainActor
final class StreamStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var store: StreamStore!
    private let roundID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        container = Storage.inMemoryContainer()
        store = StreamStore(context: ModelContext(container))
    }

    override func tearDown() async throws {
        store = nil
        container = nil
        try await super.tearDown()
    }

    func testUnknownRoundHasNoRecords() {
        XCTAssertEqual(store.count(for: roundID), 0)
        XCTAssertFalse(store.hasStream(for: roundID))
        XCTAssertTrue(store.records(for: roundID).isEmpty)
    }

    func testAppendIsSavedAtOnce() throws {
        store.append(StreamFixtures.fixes(0..<3), roundID: roundID)

        XCTAssertEqual(StreamStore(context: ModelContext(container)).count(for: roundID), 3)
        XCTAssertEqual(store.roundIDs(), [roundID])
    }

    func testPointsAndSwingsAreReadApart() {
        store.append([StreamFixtures.fix(0), StreamFixtures.swing(1), StreamFixtures.fix(2)], roundID: roundID)

        XCTAssertEqual(store.points(for: roundID).map(\.timestamp),
                       [StreamFixtures.start, StreamFixtures.start.addingTimeInterval(2)])
        XCTAssertEqual(store.swings(for: roundID).map(\.timestamp), [StreamFixtures.start.addingTimeInterval(1)])
    }

    func testReadingUntilEndTimeLeavesOutLaterRecords() {
        store.append(StreamFixtures.fixes(0..<5) + [StreamFixtures.swing(5)], roundID: roundID)

        let end = StreamFixtures.start.addingTimeInterval(2)
        XCTAssertEqual(store.points(for: roundID, until: end).count, 3)
        XCTAssertTrue(store.swings(for: roundID, until: end).isEmpty)
    }

    func testPartialRecordAtEndIsDropped() {
        var data = StreamRecord.data(for: StreamFixtures.fixes(0..<2))
        data.append(Data(count: 7))

        store.appendData(data, roundID: roundID)
        store.append([StreamFixtures.fix(2)], roundID: roundID)

        XCTAssertEqual(store.count(for: roundID), 3)
        XCTAssertEqual(StreamStore(context: ModelContext(container)).records(for: roundID), StreamFixtures.fixes(0..<3))
    }

    func testDataSliceStartsAtPositionAndIsCapped() {
        store.append(StreamFixtures.fixes(0..<10), roundID: roundID)

        let slice = store.data(for: roundID, from: 4, maxBytes: 3 * StreamRecord.size)

        XCTAssertEqual(StreamRecord.records(in: slice), StreamFixtures.fixes(4..<7))
        XCTAssertTrue(store.data(for: roundID, from: 10, maxBytes: 1_000).isEmpty)
    }

    func testTruncateKeepsFirstRecords() {
        store.append(StreamFixtures.fixes(0..<5), roundID: roundID)

        store.truncate(roundID, to: 2)

        XCTAssertEqual(store.records(for: roundID), StreamFixtures.fixes(0..<2))
        XCTAssertEqual(StreamStore(context: ModelContext(container)).count(for: roundID), 2)
    }

    func testTruncateAfterDateDropsFromFirstLaterRecord() {
        store.append(StreamFixtures.fixes(0..<5), roundID: roundID)

        let count = store.truncate(roundID, after: StreamFixtures.start.addingTimeInterval(2))

        XCTAssertEqual(count, 3)
        XCTAssertEqual(store.count(for: roundID), 3)
    }

    func testDeleteRemovesRecords() {
        store.append(StreamFixtures.fixes(0..<2), roundID: roundID)

        store.delete(roundID)

        XCTAssertEqual(store.count(for: roundID), 0)
        XCTAssertFalse(store.hasStream(for: roundID))
    }

    func testChangesBumpRevision() {
        let start = store.revision
        store.append(StreamFixtures.fixes(0..<2), roundID: roundID)
        store.truncate(roundID, to: 1)
        XCTAssertEqual(store.revision, start + 2)
    }
}

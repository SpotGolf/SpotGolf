import XCTest
import CoreLocation
@testable import SpotGolf

@MainActor
final class TrackStoreTests: XCTestCase {

    private var directory: URL!
    private var store: TrackStore!
    private let roundID = UUID()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = TrackStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        super.tearDown()
    }

    private func makeLocation(seconds: TimeInterval) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39.95545, longitude: -105.0422),
                   altitude: 1620,
                   horizontalAccuracy: 5,
                   verticalAccuracy: 3,
                   course: 90,
                   speed: 1.5,
                   timestamp: Date(timeIntervalSince1970: seconds))
    }

    private func makeLocations(count: Int, startingAt start: TimeInterval = 1_700_000_000) -> [CLLocation] {
        (0..<count).map { makeLocation(seconds: start + TimeInterval($0)) }
    }

    // MARK: - Recording

    func testNoTrackForUnknownRound() {
        XCTAssertTrue(store.points(for: UUID(), source: .phone).isEmpty)
    }

    func testAppendAndRead() {
        store.append(makeLocations(count: 3), roundID: roundID, source: .phone)

        let points = store.points(for: roundID, source: .phone)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].timestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(points[2].timestamp, Date(timeIntervalSince1970: 1_700_000_002))
        XCTAssertEqual(points[0].latitude, 39.95545)
        XCTAssertEqual(points[0].longitude, -105.0422)
        XCTAssertEqual(points[0].altitude, 1620)
    }

    func testSmallBatchIsNotWrittenUntilFlush() {
        store.append(makeLocations(count: TrackStore.flushThreshold - 1), roundID: roundID, source: .phone)
        let url = store.fileURL(for: roundID, source: .phone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWritesOnceThresholdIsReached() {
        store.append(makeLocations(count: TrackStore.flushThreshold), roundID: roundID, source: .phone)

        let url = store.fileURL(for: roundID, source: .phone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testFileHasOneHeaderAfterManyFlushes() throws {
        store.append(makeLocations(count: 2), roundID: roundID, source: .phone)
        store.flush()
        store.append(makeLocations(count: 2, startingAt: 1_700_000_100), roundID: roundID, source: .phone)
        store.flush()

        let data = try Data(contentsOf: store.fileURL(for: roundID, source: .phone))
        XCTAssertEqual(data.count, 4 + 4 * TrackPoint.recordSize)
        XCTAssertEqual(data.littleEndianInteger(at: 0) as Int32, TrackPoint.fileVersion)
    }

    func testUnknownVersionIsNotRead() throws {
        store.append(makeLocations(count: 2), roundID: roundID, source: .phone)
        store.flush()
        let url = store.fileURL(for: roundID, source: .phone)

        var data = try Data(contentsOf: url)
        data[0] = 99
        try data.write(to: url)

        XCTAssertTrue(TrackStore(directory: directory).points(for: roundID, source: .phone).isEmpty)
    }

    func testPartialRecordIsDroppedOnNextWrite() throws {
        store.append(makeLocations(count: 2), roundID: roundID, source: .phone)
        store.flush()
        let url = store.fileURL(for: roundID, source: .phone)

        // Leave half a record at the end, as a write that was cut short would
        var data = try Data(contentsOf: url)
        data.append(Data(count: TrackPoint.recordSize / 2))
        try data.write(to: url)

        store.append(makeLocations(count: 1, startingAt: 1_700_000_100), roundID: roundID, source: .phone)
        let seconds = store.points(for: roundID, source: .phone).map(\.timestamp.timeIntervalSince1970)
        XCTAssertEqual(seconds, [1_700_000_000, 1_700_000_001, 1_700_000_100])
    }

    func testTrackSurvivesNewStoreInstance() {
        store.append(makeLocations(count: 3), roundID: roundID, source: .phone)
        store.flush()

        let reopened = TrackStore(directory: directory)
        XCTAssertEqual(reopened.points(for: roundID, source: .phone).count, 3)
    }

    func testRoundsAndSourcesAreKeptApart() {
        let otherRound = UUID()
        store.append(makeLocations(count: 1), roundID: roundID, source: .phone)
        store.append(makeLocations(count: 2), roundID: roundID, source: .watch)
        store.append(makeLocations(count: 3), roundID: otherRound, source: .phone)

        XCTAssertEqual(store.points(for: roundID, source: .phone).count, 1)
        XCTAssertEqual(store.points(for: roundID, source: .watch).count, 2)
        XCTAssertEqual(store.points(for: otherRound, source: .phone).count, 3)
    }

    // MARK: - Delete

    func testDeleteRoundRemovesAllSources() {
        let otherRound = UUID()
        store.append(makeLocations(count: 2), roundID: roundID, source: .phone)
        store.append(makeLocations(count: 2), roundID: roundID, source: .watch)
        store.append(makeLocations(count: 2), roundID: otherRound, source: .phone)

        store.deleteRound(roundID)

        XCTAssertTrue(store.points(for: roundID, source: .phone).isEmpty)
        XCTAssertTrue(store.points(for: roundID, source: .watch).isEmpty)
        XCTAssertEqual(store.points(for: otherRound, source: .phone).count, 2)
    }

    func testDeleteRoundDropsUnwrittenFixes() {
        store.append(makeLocations(count: 2), roundID: roundID, source: .phone)

        store.deleteRound(roundID)
        store.flush()

        XCTAssertTrue(store.points(for: roundID, source: .phone).isEmpty)
    }

    // MARK: - Transfer

    func testFileNameParsing() {
        let live = store.fileURL(for: roundID, source: .watch)
        XCTAssertEqual(TrackStore.parseFileName(live)?.roundID, roundID)
        XCTAssertEqual(TrackStore.parseFileName(live)?.source, .watch)

        let segment = directory.appendingPathComponent("\(roundID.uuidString)_watch_1700000000.track")
        XCTAssertEqual(TrackStore.parseFileName(segment)?.roundID, roundID)
        XCTAssertEqual(TrackStore.parseFileName(segment)?.source, .watch)

        XCTAssertNil(TrackStore.parseFileName(directory.appendingPathComponent("notes.track")))
    }

    func testFinishedTrackMovesToOutbox() {
        store.append(makeLocations(count: 2), roundID: roundID)

        store.moveFinishedTracksToOutbox(activeRoundID: nil)

        let outbox = store.outboxFiles()
        XCTAssertEqual(outbox.count, 1)
        XCTAssertEqual(TrackStore.parseFileName(outbox[0])?.roundID, roundID)
        XCTAssertTrue(store.points(for: roundID, source: .current).isEmpty)
    }

    func testActiveRoundStaysOutOfOutbox() {
        store.append(makeLocations(count: 2), roundID: roundID)

        store.moveFinishedTracksToOutbox(activeRoundID: roundID)

        XCTAssertTrue(store.outboxFiles().isEmpty)
        XCTAssertEqual(store.points(for: roundID, source: .current).count, 2)
    }

    func testOtherDeviceTrackStaysOutOfOutbox() {
        let other: TrackSource = TrackSource.current == .phone ? .watch : .phone
        store.append(makeLocations(count: 2), roundID: roundID, source: other)

        store.moveFinishedTracksToOutbox(activeRoundID: nil)

        XCTAssertTrue(store.outboxFiles().isEmpty)
        XCTAssertEqual(store.points(for: roundID, source: other).count, 2)
    }

    func testRemoveOutboxFile() {
        store.append(makeLocations(count: 2), roundID: roundID)
        store.moveFinishedTracksToOutbox(activeRoundID: nil)
        let url = store.outboxFiles()[0]

        store.removeOutboxFile(url)

        XCTAssertTrue(store.outboxFiles().isEmpty)
    }

    func testDeleteRoundRemovesOutboxFiles() {
        store.append(makeLocations(count: 2), roundID: roundID)
        store.moveFinishedTracksToOutbox(activeRoundID: nil)

        store.deleteRound(roundID)

        XCTAssertTrue(store.outboxFiles().isEmpty)
    }

    // MARK: - Import

    /// Builds a track file the way the watch would send it.
    private func makeSegment(count: Int, startingAt start: TimeInterval) -> URL {
        let sender = TrackStore(directory: directory.appendingPathComponent("sender-\(UUID().uuidString)"))
        sender.append(makeLocations(count: count, startingAt: start), roundID: roundID, source: .watch)
        sender.flush()
        return sender.fileURL(for: roundID, source: .watch)
    }

    func testImportSegment() {
        let segment = makeSegment(count: 3, startingAt: 1_700_000_000)

        store.importSegment(from: segment, roundID: roundID, source: .watch)

        XCTAssertEqual(store.points(for: roundID, source: .watch).count, 3)
    }

    func testImportSameSegmentTwiceAddsNothing() {
        let segment = makeSegment(count: 3, startingAt: 1_700_000_000)

        store.importSegment(from: segment, roundID: roundID, source: .watch)
        store.importSegment(from: segment, roundID: roundID, source: .watch)

        XCTAssertEqual(store.points(for: roundID, source: .watch).count, 3)
    }

    func testImportSecondSegmentAppends() {
        store.importSegment(from: makeSegment(count: 3, startingAt: 1_700_000_000), roundID: roundID, source: .watch)
        store.importSegment(from: makeSegment(count: 2, startingAt: 1_700_000_100), roundID: roundID, source: .watch)

        XCTAssertEqual(store.points(for: roundID, source: .watch).count, 5)
    }

    func testImportOutOfOrderSegmentsSortsByTime() {
        store.importSegment(from: makeSegment(count: 2, startingAt: 1_700_000_100), roundID: roundID, source: .watch)
        store.importSegment(from: makeSegment(count: 2, startingAt: 1_700_000_000), roundID: roundID, source: .watch)

        let seconds = store.points(for: roundID, source: .watch).map(\.timestamp.timeIntervalSince1970)
        XCTAssertEqual(seconds, [1_700_000_000, 1_700_000_001, 1_700_000_100, 1_700_000_101])
    }

    func testImportKeepsOneHeader() throws {
        store.importSegment(from: makeSegment(count: 2, startingAt: 1_700_000_000), roundID: roundID, source: .watch)
        store.importSegment(from: makeSegment(count: 2, startingAt: 1_700_000_100), roundID: roundID, source: .watch)

        let data = try Data(contentsOf: store.fileURL(for: roundID, source: .watch))
        XCTAssertEqual(data.count, 4 + 4 * TrackPoint.recordSize)
    }

    func testImportMissingFileDoesNothing() {
        store.importSegment(from: directory.appendingPathComponent("missing.track"), roundID: roundID, source: .watch)

        XCTAssertTrue(store.points(for: roundID, source: .watch).isEmpty)
    }
}

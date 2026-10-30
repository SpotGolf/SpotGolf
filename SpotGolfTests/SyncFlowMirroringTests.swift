import XCTest
import CoreLocation
@testable import SpotGolf

/// The main sync flows with the workout mirrored, while WatchConnectivity says the other app
/// is not reachable, as it does with the watch screen off. `SyncFlowTests` covers every flow
/// over WatchConnectivity.
@MainActor
final class SyncFlowMirroringTests: XCTestCase {

    private var pair: SyncPair!

    override func setUp() async throws {
        try await super.setUp()
        pair = SyncPair()
        pair.connectMirroring()
        pair.setReachable(false)
    }

    override func tearDown() async throws {
        pair.cleanUp()
        pair = nil
        try await super.tearDown()
    }

    private func phoneRound(_ id: UUID) -> Round? { pair.phoneRounds.round(id) }
    private func watchRound(_ id: UUID) -> Round? { pair.watchRounds.round(id) }

    private func locations(_ seconds: Range<Int>) -> [CLLocation] {
        seconds.map { StreamFixtures.location(TimeInterval($0)) }
    }

    func testBothSidesAreConnectedOverMirroring() {
        XCTAssertTrue(pair.phoneSync.isConnected)
        XCTAssertTrue(pair.watchSync.isConnected)
    }

    func testStartRoundIsConfirmedOverMirroring() {
        let id = pair.startRound()

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(watchRound(id)?.status, .active)
        XCTAssertTrue(pair.phoneTransport.sent.isEmpty)
    }

    func testStartWaitingForTheWatchGoesOnceMirroringConnects() {
        pair.dropMirroring()
        let id = pair.startRound()
        XCTAssertEqual(phoneRound(id)?.status, .starting)

        pair.connectMirroring()

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(watchRound(id)?.status, .active)
    }

    func testLargeCourseIsSentInChunksOverMirroring() throws {
        let id = pair.startRound(try largeSelection())

        XCTAssertEqual(watchRound(id)?.status, .active)
        XCTAssertTrue(pair.phoneTransport.sent.isEmpty)
    }

    func testFixesStreamOverMirroring() {
        let id = pair.startRound()

        pair.watch.record(locations(0..<10))

        XCTAssertEqual(pair.phoneStreams.count(for: id), 10)
        XCTAssertTrue(pair.watchTransport.sent.isEmpty)
    }

    func testDroppedMirroringFallsBackToWatchConnectivity() {
        let id = pair.startRound()
        pair.dropMirroring()
        pair.setReachable(true)

        pair.watch.record(locations(0..<5))

        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        XCTAssertFalse(pair.watchTransport.sent.isEmpty)
    }

    func testRecordsWhileDisconnectedCatchUpWhenMirroringReconnects() {
        let id = pair.startRound()
        pair.dropMirroring()
        pair.watch.record(locations(0..<50))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 0)

        pair.connectMirroring()
        // The phone's ack on reconnect can arrive while the watch's first batch is in flight;
        // then the rest goes on the retry timer
        pair.watch.sender.pump()

        XCTAssertEqual(pair.phoneStreams.count(for: id), 50)
    }

    func testPhoneEndGetsTheWholeStreamOverMirroring() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<5))

        pair.phone.endRound(id)

        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(watchRound(id)?.status, .ended)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))
    }

    func testWatchEndGetsTheWholeStreamOverMirroring() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<5))
        var completed: [UUID] = []
        pair.watch.onStreamComplete = { completed.append($0) }

        pair.watch.endRound()

        XCTAssertEqual(watchRound(id)?.endConfirmed, true)
        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))
        XCTAssertEqual(completed, [id])
    }
}

import XCTest
import CoreLocation
@testable import SpotGolf

@MainActor
final class RoundStoreTests: XCTestCase {

    private var store: RoundStore!
    private var syncMessages: [SyncMessage]!

    override func setUp() {
        super.setUp()
        store = RoundStore()
        // Clear any persisted data from previous runs
        store.rounds = []
        syncMessages = []
        store.onSyncEvent = { [weak self] msg in
            self?.syncMessages.append(msg)
        }
    }

    override func tearDown() {
        store = nil
        syncMessages = nil
        super.tearDown()
    }

    // MARK: - startRound

    func testStartRoundCreatesActiveRound() {
        store.startRound()

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertNotNil(store.activeRound)
        XCTAssertTrue(store.rounds[0].isActive)
    }

    func testStartRoundWithExplicitIDAndDate() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        store.startRound(id: id, date: date)

        XCTAssertEqual(store.rounds[0].id, id)
        XCTAssertEqual(store.rounds[0].date, date)
    }

    func testStartRoundEndsPreviousActiveRound() {
        store.startRound()
        let firstID = store.rounds[0].id

        store.startRound()

        XCTAssertEqual(store.rounds.count, 2)
        // The new round is at index 0 (inserted at front)
        XCTAssertTrue(store.rounds[0].isActive)
        // The old round should be ended
        let oldRound = store.rounds.first(where: { $0.id == firstID })
        XCTAssertNotNil(oldRound)
        XCTAssertFalse(oldRound!.isActive)
    }

    func testStartRoundFiresSyncEvent() {
        store.startRound()

        XCTAssertEqual(syncMessages.count, 1)
        if case .startRound(let id, _) = syncMessages[0] {
            XCTAssertEqual(id, store.rounds[0].id)
        } else {
            XCTFail("Expected startRound sync message")
        }
    }

    func testStartRoundFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertTrue(syncMessages.isEmpty)
    }

    // MARK: - endRound

    func testEndRound() {
        store.startRound()
        syncMessages.removeAll()

        store.endRound()

        XCTAssertNil(store.activeRound)
        XCTAssertFalse(store.rounds[0].isActive)
    }

    func testEndRoundByID() {
        store.startRound()
        let id = store.rounds[0].id
        syncMessages.removeAll()

        store.endRound(roundID: id)

        XCTAssertFalse(store.rounds[0].isActive)
    }

    func testEndRoundFiresSyncEvent() {
        store.startRound()
        let id = store.rounds[0].id
        syncMessages.removeAll()

        store.endRound()

        XCTAssertEqual(syncMessages.count, 1)
        if case .endRound(let syncedID) = syncMessages[0] {
            XCTAssertEqual(syncedID, id)
        } else {
            XCTFail("Expected endRound sync message")
        }
    }

    func testEndRoundFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)

        store.endRound(fromSync: true)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testEndRoundNoActiveRoundIsNoOp() {
        store.endRound()
        XCTAssertTrue(syncMessages.isEmpty)
    }

    // MARK: - addMark (active round)

    func testAddMarkToActiveRound() {
        store.startRound()
        syncMessages.removeAll()

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)

        XCTAssertEqual(store.activeRound?.marks.count, 1)
        XCTAssertEqual(store.activeRound?.marks[0].id, mark.id)
    }

    func testAddMarkFiresSyncEvent() {
        store.startRound()
        let roundID = store.rounds[0].id
        syncMessages.removeAll()

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)

        XCTAssertEqual(syncMessages.count, 1)
        if case .addMark(let syncedMark, let syncedRoundID) = syncMessages[0] {
            XCTAssertEqual(syncedMark.id, mark.id)
            XCTAssertEqual(syncedRoundID, roundID)
        } else {
            XCTFail("Expected addMark sync message")
        }
    }

    func testAddMarkFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark, fromSync: true)

        XCTAssertEqual(store.activeRound?.marks.count, 1)
        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testAddMarkNoActiveRoundIsNoOp() {
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    // MARK: - addMark (to specific round)

    func testAddMarkToSpecificRound() {
        store.startRound()
        let roundID = store.rounds[0].id
        store.endRound(fromSync: true)
        syncMessages.removeAll()

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, mark: mark)

        XCTAssertEqual(store.rounds[0].marks.count, 1)
    }

    func testAddMarkToSpecificRoundFiresSyncEvent() {
        store.startRound()
        let roundID = store.rounds[0].id
        syncMessages.removeAll()

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, mark: mark)

        XCTAssertEqual(syncMessages.count, 1)
        if case .addMark(_, let syncedRoundID) = syncMessages[0] {
            XCTAssertEqual(syncedRoundID, roundID)
        } else {
            XCTFail("Expected addMark sync message")
        }
    }

    func testAddMarkToSpecificRoundFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)
        let roundID = store.rounds[0].id

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, mark: mark, fromSync: true)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testAddMarkToNonexistentRoundIsNoOp() {
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: UUID(), mark: mark)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    // MARK: - nextHole / previousHole

    func testNextHole() {
        store.startRound()
        syncMessages.removeAll()

        store.nextHole()

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 1)
        XCTAssertEqual(store.rounds[0].holes.count, 2)
    }

    func testNextHoleFiresSyncEvent() {
        store.startRound()
        let roundID = store.rounds[0].id
        syncMessages.removeAll()

        store.nextHole()

        XCTAssertEqual(syncMessages.count, 1)
        if case .nextHole(let syncedID) = syncMessages[0] {
            XCTAssertEqual(syncedID, roundID)
        } else {
            XCTFail("Expected nextHole sync message")
        }
    }

    func testNextHoleFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)

        store.nextHole(fromSync: true)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testPreviousHole() {
        store.startRound()
        store.nextHole(fromSync: true)
        syncMessages.removeAll()

        store.previousHole()

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 0)
    }

    func testPreviousHoleFiresSyncEvent() {
        store.startRound()
        store.nextHole(fromSync: true)
        let roundID = store.rounds[0].id
        syncMessages.removeAll()

        store.previousHole()

        XCTAssertEqual(syncMessages.count, 1)
        if case .previousHole(let syncedID) = syncMessages[0] {
            XCTAssertEqual(syncedID, roundID)
        } else {
            XCTFail("Expected previousHole sync message")
        }
    }

    func testPreviousHoleFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)
        store.nextHole(fromSync: true)

        store.previousHole(fromSync: true)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testPreviousHoleAtZeroDoesNotSync() {
        store.startRound()
        syncMessages.removeAll()

        store.previousHole()

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testNextHoleAt18DoesNotSync() {
        store.startRound()
        store.rounds[0] = Round(id: store.rounds[0].id, date: store.rounds[0].date,
                                holes: (0..<18).map { _ in Hole() }, currentHoleIndex: 17)
        syncMessages.removeAll()

        store.nextHole()

        XCTAssertTrue(syncMessages.isEmpty)
        XCTAssertEqual(store.rounds[0].currentHoleIndex, 17)
    }

    func testNextHoleByRoundID() {
        store.startRound()
        let roundID = store.rounds[0].id
        syncMessages.removeAll()

        store.nextHole(roundID: roundID)

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 1)
    }

    func testPreviousHoleByRoundID() {
        store.startRound()
        let roundID = store.rounds[0].id
        store.nextHole(fromSync: true)
        syncMessages.removeAll()

        store.previousHole(roundID: roundID)

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 0)
    }

    // MARK: - moveMark

    func testMoveMark() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)

        let newCoord = CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0)
        store.moveMark(mark, to: newCoord, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].latitude, 34.0)
        XCTAssertEqual(store.rounds[0].marks[0].longitude, -113.0)
        // ID should be preserved
        XCTAssertEqual(store.rounds[0].marks[0].id, mark.id)
    }

    func testMoveMarkPreservesTimestamp() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)

        let newCoord = CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0)
        store.moveMark(mark, to: newCoord, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].timestamp, mark.timestamp)
    }

    func testMoveMarkAcrossHoles() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)
        store.nextHole(fromSync: true)

        // Mark is in hole 0, but we're on hole 1 — should still find it
        let newCoord = CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0)
        store.moveMark(mark, to: newCoord, in: roundID)

        XCTAssertEqual(store.rounds[0].holes[0].marks[0].latitude, 34.0)
    }

    // MARK: - reorderMark

    func testReorderMark() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark0 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: -114.0))
        store.addMark(mark0)
        store.addMark(mark1)
        store.addMark(mark2)

        // Move mark2 from index 2 to index 0
        store.reorderMark(mark2, to: 0, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].id, mark2.id)
        XCTAssertEqual(store.rounds[0].marks[1].id, mark0.id)
        XCTAssertEqual(store.rounds[0].marks[2].id, mark1.id)
    }

    func testReorderMarkClampsToValidRange() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark0 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        store.addMark(mark0)
        store.addMark(mark1)

        // Try to move to an out-of-bounds index
        store.reorderMark(mark0, to: 100, in: roundID)

        // Should be clamped to last index
        XCTAssertEqual(store.rounds[0].marks[1].id, mark0.id)
    }

    func testReorderMarkClampsNegativeIndex() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark0 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        store.addMark(mark0)
        store.addMark(mark1)

        store.reorderMark(mark1, to: -5, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].id, mark1.id)
    }

    // MARK: - removeMark

    func testRemoveMark() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)

        store.removeMark(mark, from: roundID)

        XCTAssertTrue(store.rounds[0].marks.isEmpty)
    }

    func testRemoveMarkLeavesOtherMarks() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark1 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0))
        let mark2 = BallMark(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0))
        store.addMark(mark1)
        store.addMark(mark2)

        store.removeMark(mark1, from: roundID)

        XCTAssertEqual(store.rounds[0].marks.count, 1)
        XCTAssertEqual(store.rounds[0].marks[0].id, mark2.id)
    }

    func testRemoveMarkAcrossHoles() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)
        store.nextHole(fromSync: true)

        // Mark is in hole 0, we're on hole 1
        store.removeMark(mark, from: roundID)

        XCTAssertTrue(store.rounds[0].holes[0].marks.isEmpty)
    }

    // MARK: - deleteRound

    func testDeleteRound() {
        store.startRound()
        let round = store.rounds[0]

        store.deleteRound(round)

        XCTAssertTrue(store.rounds.isEmpty)
    }

    func testDeleteRoundLeavesOtherRounds() {
        store.startRound()
        store.startRound()
        XCTAssertEqual(store.rounds.count, 2)

        let roundToDelete = store.rounds[1]
        store.deleteRound(roundToDelete)

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertNotEqual(store.rounds[0].id, roundToDelete.id)
    }

    // MARK: - activeRound

    func testActiveRoundReturnsNilWhenNoRounds() {
        XCTAssertNil(store.activeRound)
    }

    func testActiveRoundReturnsNilWhenAllEnded() {
        store.startRound()
        store.endRound()

        XCTAssertNil(store.activeRound)
    }

    func testActiveRoundReturnsTheActiveOne() {
        store.startRound()
        let id = store.rounds[0].id

        XCTAssertEqual(store.activeRound?.id, id)
    }

    // MARK: - Sync handler not set

    func testMutationsWorkWithoutSyncHandler() {
        store.onSyncEvent = nil

        store.startRound()
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)
        store.endRound()

        // Should not crash
        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertFalse(store.rounds[0].isActive)
        XCTAssertEqual(store.rounds[0].marks.count, 1)
    }

    // MARK: - Bidirectional sync scenario

    func testFullSyncScenario() {
        // Simulate phone starts round
        store.startRound()
        let roundID = store.rounds[0].id
        XCTAssertEqual(syncMessages.count, 1)
        syncMessages.removeAll()

        // Simulate watch adds a mark (fromSync)
        let watchMark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, mark: watchMark, fromSync: true)
        XCTAssertTrue(syncMessages.isEmpty, "fromSync should not trigger sync event")

        // Phone adds a mark (local)
        let phoneMark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.46, longitude: -112.08))
        store.addMark(phoneMark)
        XCTAssertEqual(syncMessages.count, 1, "Local action should trigger sync event")
        syncMessages.removeAll()

        // Simulate watch ends round (fromSync)
        store.endRound(roundID: roundID, fromSync: true)
        XCTAssertTrue(syncMessages.isEmpty, "fromSync should not trigger sync event")

        // Verify final state
        XCTAssertNil(store.activeRound)
        XCTAssertEqual(store.rounds[0].marks.count, 2)
    }
}

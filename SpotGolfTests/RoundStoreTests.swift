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
        if case .addMark(let syncedMark, let holeIndex, let syncedRoundID) = syncMessages[0] {
            XCTAssertEqual(syncedMark.id, mark.id)
            XCTAssertEqual(holeIndex, 0)
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
        store.addMark(to: roundID, holeIndex: 0, mark: mark)

        XCTAssertEqual(store.rounds[0].marks.count, 1)
    }

    func testAddMarkToSpecificRoundFiresSyncEvent() {
        store.startRound()
        let roundID = store.rounds[0].id
        syncMessages.removeAll()

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, holeIndex: 0, mark: mark)

        XCTAssertEqual(syncMessages.count, 1)
        if case .addMark(_, let holeIndex, let syncedRoundID) = syncMessages[0] {
            XCTAssertEqual(holeIndex, 0)
            XCTAssertEqual(syncedRoundID, roundID)
        } else {
            XCTFail("Expected addMark sync message")
        }
    }

    func testAddMarkToSpecificRoundFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)
        let roundID = store.rounds[0].id

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, holeIndex: 0, mark: mark, fromSync: true)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testAddMarkToNonexistentRoundIsNoOp() {
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: UUID(), holeIndex: 0, mark: mark)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testAddMarkToSpecificHoleIndex() {
        store.startRound()
        let roundID = store.rounds[0].id
        store.nextHole() // now on hole 1
        syncMessages.removeAll()

        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(to: roundID, holeIndex: 0, mark: mark, fromSync: true) // add to hole 0

        XCTAssertEqual(store.rounds[0].holes[0].marks.count, 1, "Mark should be added to hole 0")
        XCTAssertTrue(store.rounds[0].holes[1].marks.isEmpty, "Hole 1 should have no marks")
    }

    // MARK: - nextHole / previousHole

    func testNextRoundHole() {
        store.startRound()
        syncMessages.removeAll()

        store.nextHole()

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 1)
        XCTAssertEqual(store.rounds[0].holes.count, 2)
    }

    func testNextHoleFiresSyncEvent() {
        store.startRound()
        syncMessages.removeAll()

        store.nextHole()

        XCTAssertEqual(syncMessages.count, 1)
        guard case .setHole(let holeIndex, let roundID, _) = syncMessages[0] else {
            return XCTFail("Expected a setHole message")
        }
        XCTAssertEqual(holeIndex, 1)
        XCTAssertEqual(roundID, store.rounds[0].id)
    }

    func testPreviousRoundHole() {
        store.startRound()
        store.nextHole()
        syncMessages.removeAll()

        store.previousHole()

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 0)
    }

    func testPreviousHoleFiresSyncEvent() {
        store.startRound()
        store.nextHole()
        syncMessages.removeAll()

        store.previousHole()

        XCTAssertEqual(syncMessages.count, 1)
        guard case .setHole(let holeIndex, _, _) = syncMessages[0] else {
            return XCTFail("Expected a setHole message")
        }
        XCTAssertEqual(holeIndex, 0)
    }

    func testPreviousHoleAtZeroIsNoOp() {
        store.startRound()
        syncMessages.removeAll()

        store.previousHole()

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 0)
        XCTAssertTrue(syncMessages.isEmpty)
    }

    // MARK: - setHoleIndex

    func testSetHoleIndexFiresSyncEvent() {
        store.startRound()
        syncMessages.removeAll()

        store.setHoleIndex(4)

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 4)
        XCTAssertEqual(syncMessages.count, 1)
        guard case .setHole(let holeIndex, let roundID, _) = syncMessages[0] else {
            return XCTFail("Expected a setHole message")
        }
        XCTAssertEqual(holeIndex, 4)
        XCTAssertEqual(roundID, store.rounds[0].id)
    }

    func testSetHoleIndexToTheSameHoleDoesNotFireSyncEvent() {
        store.startRound()
        store.setHoleIndex(4)
        syncMessages.removeAll()

        store.setHoleIndex(4)

        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testSetHoleIndexFromSyncDoesNotFireSyncEvent() {
        store.startRound()
        syncMessages.removeAll()

        store.setHoleIndex(4, roundID: store.rounds[0].id, changedAt: Date().addingTimeInterval(1), fromSync: true)

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 4)
        XCTAssertTrue(syncMessages.isEmpty)
    }

    func testRepeatedHoleChangeFromSyncIsIgnored() {
        store.startRound()
        let roundID = store.rounds[0].id
        let chosenAt = Date().addingTimeInterval(1)
        store.setHoleIndex(4, roundID: roundID, changedAt: chosenAt, fromSync: true)

        // The player moves on locally, then the queued copy of the same message arrives
        store.setHoleIndex(5)
        store.setHoleIndex(4, roundID: roundID, changedAt: chosenAt, fromSync: true)

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 5)
    }

    func testOlderHoleChangeFromSyncIsIgnored() {
        store.startRound()
        let roundID = store.rounds[0].id
        store.setHoleIndex(5)

        store.setHoleIndex(2, roundID: roundID, changedAt: Date().addingTimeInterval(-10), fromSync: true)

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 5)
    }

    func testNewerHoleChangeFromSyncIsApplied() {
        store.startRound()
        let roundID = store.rounds[0].id
        store.setHoleIndex(5)

        store.setHoleIndex(2, roundID: roundID, changedAt: Date().addingTimeInterval(10), fromSync: true)

        XCTAssertEqual(store.rounds[0].currentHoleIndex, 2)
    }

    func testNextHoleAt18IsNoOp() {
        store.startRound()
        store.rounds[0] = Round(id: store.rounds[0].id, date: store.rounds[0].date,
                                holes: (0..<18).map { _ in RoundHole() }, currentHoleIndex: 17)

        store.nextHole()

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
        store.nextHole()
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
        store.nextHole()

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
        store.nextHole()

        // Mark is in hole 0, we're on hole 1
        store.removeMark(mark, from: roundID)

        XCTAssertTrue(store.rounds[0].holes[0].marks.isEmpty)
    }

    // MARK: - setMarkType

    func testSetMarkType() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)
        syncMessages.removeAll()

        store.setMarkType(markID: mark.id, type: .penalty, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].type, .penalty)
    }

    func testSetMarkTypeToOutOfBounds() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)

        store.setMarkType(markID: mark.id, type: .outOfBounds, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].type, .outOfBounds)
    }

    func testSetMarkTypeBackToRegular() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)
        store.setMarkType(markID: mark.id, type: .penalty, in: roundID)

        store.setMarkType(markID: mark.id, type: .regular, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].type, .regular)
    }

    func testSetMarkTypeFiresSyncEvent() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)
        syncMessages.removeAll()

        store.setMarkType(markID: mark.id, type: .penalty, in: roundID)

        XCTAssertEqual(syncMessages.count, 1)
        if case .setMarkType(let markID, let type, let syncedRoundID) = syncMessages[0] {
            XCTAssertEqual(markID, mark.id)
            XCTAssertEqual(type, .penalty)
            XCTAssertEqual(syncedRoundID, roundID)
        } else {
            XCTFail("Expected setMarkType sync message")
        }
    }

    func testSetMarkTypeFromSyncDoesNotFireSyncEvent() {
        store.startRound(fromSync: true)
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark, fromSync: true)

        store.setMarkType(markID: mark.id, type: .outOfBounds, in: roundID, fromSync: true)

        XCTAssertTrue(syncMessages.isEmpty)
        XCTAssertEqual(store.rounds[0].marks[0].type, .outOfBounds)
    }

    func testMoveMarkPreservesType() {
        store.startRound()
        let roundID = store.rounds[0].id
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        store.addMark(mark)
        store.setMarkType(markID: mark.id, type: .penalty, in: roundID)

        let newCoord = CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0)
        store.moveMark(store.rounds[0].marks[0], to: newCoord, in: roundID)

        XCTAssertEqual(store.rounds[0].marks[0].type, .penalty)
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
        store.addMark(to: roundID, holeIndex: 0, mark: watchMark, fromSync: true)
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

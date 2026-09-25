import XCTest
import CoreLocation
@testable import SpotGolf

@MainActor
final class RoundStoreTests: XCTestCase {

    private var directory: URL!
    private var store: RoundStore!
    private var timelineChanges: [Round]!
    private var markChanges: [Round]!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = RoundStore(directory: directory)
        timelineChanges = []
        markChanges = []
        store.onTimelineChanged = { [weak self] round in
            self?.timelineChanges.append(round)
        }
        store.onMarksChanged = { [weak self] round in
            self?.markChanges.append(round)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        timelineChanges = nil
        markChanges = nil
        directory = nil
        super.tearDown()
    }

    private func makeMark(latitude: Double = 33.45, longitude: Double = -112.07) -> BallMark {
        BallMark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    /// Starts a round and returns its ID.
    private func startRound() -> UUID {
        store.startRound(courseSelection: .test).id
    }

    // MARK: - Loading

    func testRoundsSurviveNewStoreInstance() {
        let id = startRound()
        store.addMark(to: id, holeIndex: 0, mark: makeMark())

        let reloaded = RoundStore(directory: directory)

        XCTAssertEqual(reloaded.rounds, store.rounds)
    }

    func testUnreadableSavedRoundsAreDiscarded() throws {
        try Data("not json".utf8).write(to: directory.appendingPathComponent("rounds.json"))

        XCTAssertTrue(RoundStore(directory: directory).rounds.isEmpty)
    }

    // MARK: - startRound

    func testStartRoundCreatesActiveRound() {
        store.startRound(courseSelection: .test)

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertNotNil(store.activeRound)
        XCTAssertTrue(store.rounds[0].isActive)
    }

    func testStartRoundWithExplicitIDAndDate() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        store.startRound(id: id, date: date, courseSelection: .test)

        XCTAssertEqual(store.rounds[0].id, id)
        XCTAssertEqual(store.rounds[0].date, date)
    }

    func testStartRoundWithStatus() {
        store.startRound(courseSelection: .test, status: .starting)

        XCTAssertNil(store.activeRound)
        XCTAssertEqual(store.currentRound?.status, .starting)
    }

    func testStartRoundWithExistingIDReturnsItUnchanged() {
        let id = startRound()
        store.addMark(to: id, holeIndex: 0, mark: makeMark())

        let again = store.startRound(id: id, courseSelection: .test, status: .starting)

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertEqual(again.status, .active)
        XCTAssertEqual(again.allMarks.count, 1)
    }

    func testNewRoundGoesFirst() {
        let first = startRound()
        let second = startRound()

        XCTAssertEqual(store.rounds.map(\.id), [second, first])
    }

    // MARK: - update

    func testUpdateChangesRound() {
        let id = startRound()

        store.update(id) { $0.status = .ending }

        XCTAssertEqual(store.round(id)?.status, .ending)
    }

    func testUpdateUnknownRoundIsNoOp() {
        startRound()
        let before = store.rounds

        store.update(UUID()) { $0.status = .ended }

        XCTAssertEqual(store.rounds, before)
    }

    // MARK: - Holes

    func testStartHoleMovesForwardAndReportsChange() {
        let id = startRound()

        store.startHole(2, source: .autoAdvance)

        XCTAssertEqual(store.round(id)?.currentHoleIndex, 2)
        XCTAssertEqual(timelineChanges.count, 1)
        XCTAssertEqual(timelineChanges[0].holeTimeline.last?.holeIndex, 2)
        XCTAssertEqual(timelineChanges[0].holeTimeline.last?.source, .autoAdvance)
    }

    func testStartHoleByRoundID() {
        let id = startRound()
        store.update(id) { $0.status = .ending }

        store.startHole(1, roundID: id, source: .playHole)

        XCTAssertEqual(store.round(id)?.currentHoleIndex, 1)
    }

    func testStartHoleIgnoresEarlierHole() {
        let id = startRound()
        store.startHole(3, source: .autoAdvance)
        timelineChanges.removeAll()

        store.startHole(1, source: .playHole)

        XCTAssertEqual(store.round(id)?.currentHoleIndex, 3)
        XCTAssertTrue(timelineChanges.isEmpty)
    }

    func testStartHoleWithoutActiveRoundIsNoOp() {
        store.startHole(1, source: .autoAdvance)

        XCTAssertTrue(store.rounds.isEmpty)
        XCTAssertTrue(timelineChanges.isEmpty)
    }

    func testMergeTimelineDoesNotReportChange() {
        let id = startRound()
        var other = store.round(id)!
        other.startHole(4, at: other.date.addingTimeInterval(600), source: .autoAdvance)

        XCTAssertTrue(store.mergeTimeline(other.holeTimeline, roundID: id))

        XCTAssertEqual(store.round(id)?.currentHoleIndex, 4)
        XCTAssertTrue(timelineChanges.isEmpty)
        XCTAssertFalse(store.mergeTimeline(other.holeTimeline, roundID: id))
    }

    func testSetTimelineReportsChangeOnlyWhenDifferent() {
        let id = startRound()
        var round = store.round(id)!
        round.startHole(2, at: round.date.addingTimeInterval(600), source: .estimated)

        store.setTimeline(round.holeTimeline, roundID: id)
        store.setTimeline(round.holeTimeline, roundID: id)

        XCTAssertEqual(store.round(id)?.currentHoleIndex, 2)
        XCTAssertEqual(timelineChanges.count, 1)
    }

    func testSetStartTimeStaysBetweenNeighbors() throws {
        let id = store.startRound(date: Date().addingTimeInterval(-3600), courseSelection: .test).id
        store.startHole(1, at: Date().addingTimeInterval(-1800), source: .autoAdvance)
        store.startHole(2, at: Date().addingTimeInterval(-600), source: .autoAdvance)
        let timeline = try XCTUnwrap(store.round(id)?.holeTimeline)

        // Before hole 1's start: kept just after it, so no entry is dropped
        store.setStartTime(timeline[0].startedAt.addingTimeInterval(-60), entryID: timeline[2].id, roundID: id)

        let updated = try XCTUnwrap(store.round(id)?.holeTimeline)
        XCTAssertEqual(updated.map(\.holeIndex), [0, 1, 2])
        XCTAssertEqual(updated[2].startedAt, timeline[1].startedAt.addingTimeInterval(1))
    }

    func testSetStartTimeMarksEntryUserSet() throws {
        let id = store.startRound(date: Date().addingTimeInterval(-3600), courseSelection: .test).id
        store.startHole(1, source: .autoAdvance)
        let entry = try XCTUnwrap(store.round(id)?.holeTimeline.last)
        let newTime = entry.startedAt.addingTimeInterval(-30)

        store.setStartTime(newTime, entryID: entry.id, roundID: id)

        let updated = try XCTUnwrap(store.round(id)?.holeTimeline.last)
        XCTAssertEqual(updated.startedAt, newTime)
        XCTAssertEqual(updated.source, .userSet)
        XCTAssertEqual(updated.version, entry.version + 1)
    }

    // MARK: - addMark

    func testAddMarkToSpecificRound() {
        let id = startRound()
        let mark = makeMark()

        store.addMark(to: id, holeIndex: 0, mark: mark)

        XCTAssertEqual(store.round(id)?.marks.count, 1)
        XCTAssertEqual(store.round(id)?.marks[0].id, mark.id)
    }

    func testAddMarkBumpsVersionAndReportsChange() {
        let id = startRound()

        store.addMark(to: id, holeIndex: 0, mark: makeMark())

        XCTAssertEqual(store.round(id)?.marksVersion, 1)
        XCTAssertEqual(markChanges.count, 1)
        XCTAssertEqual(markChanges[0].marksVersion, 1)
    }

    func testAddDuplicateMarkDoesNotBumpVersion() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.addMark(to: id, holeIndex: 0, mark: mark)

        XCTAssertEqual(store.round(id)?.marksVersion, 1)
        XCTAssertEqual(markChanges.count, 1)
    }

    func testAddMarkToNonexistentRoundIsNoOp() {
        store.addMark(to: UUID(), holeIndex: 0, mark: makeMark())

        XCTAssertTrue(store.rounds.isEmpty)
        XCTAssertTrue(markChanges.isEmpty)
    }

    func testAddMarkToSpecificHoleIndex() {
        let id = startRound()
        let mark = makeMark()

        store.addMark(to: id, holeIndex: 2, mark: mark)

        XCTAssertEqual(store.round(id)?.holes.count, 3)
        XCTAssertEqual(store.round(id)?.holes[2].marks.first?.id, mark.id)
    }

    // MARK: - moveMark

    func testMoveMark() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.moveMark(mark, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].marks[0].latitude, 34.0)
        XCTAssertEqual(store.rounds[0].marks[0].longitude, -113.0)
        // ID should be preserved
        XCTAssertEqual(store.rounds[0].marks[0].id, mark.id)
    }

    func testMoveMarkPreservesTimestamp() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.moveMark(mark, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].marks[0].timestamp, mark.timestamp)
    }

    func testMoveMarkAcrossHoles() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)
        store.startHole(1, source: .autoAdvance)

        // Mark is in hole 0, but we're on hole 1 — should still find it
        store.moveMark(mark, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].holes[0].marks[0].latitude, 34.0)
    }

    func testMoveMarkBumpsVersion() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.moveMark(mark, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)
        store.moveMark(mark, to: CLLocationCoordinate2D(latitude: 35.0, longitude: -114.0), in: id)

        XCTAssertEqual(store.round(id)?.marksVersion, 3)
        XCTAssertEqual(markChanges.map(\.marksVersion), [1, 2, 3])
    }

    // MARK: - reorderMark

    func testReorderMark() {
        let id = startRound()
        let mark0 = makeMark(latitude: 33.0, longitude: -112.0)
        let mark1 = makeMark(latitude: 34.0, longitude: -113.0)
        let mark2 = makeMark(latitude: 35.0, longitude: -114.0)
        store.addMark(to: id, holeIndex: 0, mark: mark0)
        store.addMark(to: id, holeIndex: 0, mark: mark1)
        store.addMark(to: id, holeIndex: 0, mark: mark2)

        // Move mark2 from index 2 to index 0
        store.reorderMark(mark2, to: 0, in: id)

        XCTAssertEqual(store.rounds[0].marks[0].id, mark2.id)
        XCTAssertEqual(store.rounds[0].marks[1].id, mark0.id)
        XCTAssertEqual(store.rounds[0].marks[2].id, mark1.id)
        XCTAssertEqual(store.round(id)?.marksVersion, 4)
    }

    func testReorderMarkClampsToValidRange() {
        let id = startRound()
        let mark0 = makeMark(latitude: 33.0, longitude: -112.0)
        let mark1 = makeMark(latitude: 34.0, longitude: -113.0)
        store.addMark(to: id, holeIndex: 0, mark: mark0)
        store.addMark(to: id, holeIndex: 0, mark: mark1)

        // Try to move to an out-of-bounds index
        store.reorderMark(mark0, to: 100, in: id)

        // Should be clamped to last index
        XCTAssertEqual(store.rounds[0].marks[1].id, mark0.id)
    }

    func testReorderMarkClampsNegativeIndex() {
        let id = startRound()
        let mark0 = makeMark(latitude: 33.0, longitude: -112.0)
        let mark1 = makeMark(latitude: 34.0, longitude: -113.0)
        store.addMark(to: id, holeIndex: 0, mark: mark0)
        store.addMark(to: id, holeIndex: 0, mark: mark1)

        store.reorderMark(mark1, to: -5, in: id)

        XCTAssertEqual(store.rounds[0].marks[0].id, mark1.id)
    }

    func testReorderToSamePlaceDoesNotBumpVersion() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.reorderMark(mark, to: 0, in: id)

        XCTAssertEqual(store.round(id)?.marksVersion, 1)
    }

    // MARK: - removeMark

    func testRemoveMark() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.removeMark(mark, from: id)

        XCTAssertTrue(store.rounds[0].marks.isEmpty)
        XCTAssertEqual(store.round(id)?.marksVersion, 2)
        XCTAssertEqual(markChanges.count, 2)
    }

    func testRemoveMarkLeavesOtherMarks() {
        let id = startRound()
        let mark1 = makeMark(latitude: 33.0, longitude: -112.0)
        let mark2 = makeMark(latitude: 34.0, longitude: -113.0)
        store.addMark(to: id, holeIndex: 0, mark: mark1)
        store.addMark(to: id, holeIndex: 0, mark: mark2)

        store.removeMark(mark1, from: id)

        XCTAssertEqual(store.rounds[0].marks.count, 1)
        XCTAssertEqual(store.rounds[0].marks[0].id, mark2.id)
    }

    func testRemoveMarkAcrossHoles() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)
        store.startHole(1, source: .autoAdvance)

        // Mark is in hole 0, we're on hole 1
        store.removeMark(mark, from: id)

        XCTAssertTrue(store.rounds[0].holes[0].marks.isEmpty)
    }

    func testRemoveMissingMarkDoesNotBumpVersion() {
        let id = startRound()

        store.removeMark(makeMark(), from: id)

        XCTAssertEqual(store.round(id)?.marksVersion, 0)
        XCTAssertTrue(markChanges.isEmpty)
    }

    // MARK: - setMarkType

    func testSetMarkType() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.setMarkType(markID: mark.id, type: .penalty, in: id)

        XCTAssertEqual(store.rounds[0].marks[0].type, .penalty)
        XCTAssertEqual(markChanges.last?.marks[0].type, .penalty)
    }

    func testSetMarkTypeToOutOfBounds() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)

        store.setMarkType(markID: mark.id, type: .outOfBounds, in: id)

        XCTAssertEqual(store.rounds[0].marks[0].type, .outOfBounds)
    }

    func testSetMarkTypeBackToRegular() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)
        store.setMarkType(markID: mark.id, type: .penalty, in: id)

        store.setMarkType(markID: mark.id, type: .regular, in: id)

        XCTAssertEqual(store.rounds[0].marks[0].type, .regular)
    }

    func testMoveMarkPreservesType() {
        let id = startRound()
        let mark = makeMark()
        store.addMark(to: id, holeIndex: 0, mark: mark)
        store.setMarkType(markID: mark.id, type: .penalty, in: id)

        store.moveMark(store.rounds[0].marks[0], to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].marks[0].type, .penalty)
    }

    // MARK: - applyMarks

    func testApplyMarksReplacesMarksWhenNewer() {
        let id = startRound()
        store.addMark(to: id, holeIndex: 0, mark: makeMark())
        let replacement = makeMark(latitude: 34.0, longitude: -113.0)
        markChanges.removeAll()

        XCTAssertTrue(store.applyMarks(MarksSnapshot(roundID: id, version: 5, holes: [[], [replacement]])))

        XCTAssertEqual(store.round(id)?.marksVersion, 5)
        XCTAssertEqual(store.round(id)?.holes.map(\.marks), [[], [replacement]])
        XCTAssertTrue(markChanges.isEmpty)
    }

    func testApplyMarksIgnoresOlderOrSameVersion() {
        let id = startRound()
        let newer = makeMark(latitude: 34.0, longitude: -113.0)
        store.applyMarks(MarksSnapshot(roundID: id, version: 6, holes: [[newer]]))

        XCTAssertFalse(store.applyMarks(MarksSnapshot(roundID: id, version: 5, holes: [[makeMark()]])))
        XCTAssertFalse(store.applyMarks(MarksSnapshot(roundID: id, version: 6, holes: [])))

        XCTAssertEqual(store.round(id)?.marks, [newer])
    }

    func testApplyEmptyMarksKeepsOneHole() {
        let id = startRound()

        store.applyMarks(MarksSnapshot(roundID: id, version: 1, holes: []))

        XCTAssertEqual(store.round(id)?.holes.count, 1)
    }

    func testApplyMarksKeepsCurrentHoleReachable() {
        let id = startRound()
        store.startHole(3, source: .autoAdvance)

        store.applyMarks(MarksSnapshot(roundID: id, version: 1, holes: [[makeMark()]]))

        XCTAssertEqual(store.round(id)?.holes.count, 4)
    }

    func testApplyMarksForUnknownRoundIsIgnored() {
        XCTAssertFalse(store.applyMarks(MarksSnapshot(roundID: UUID(), version: 1, holes: [])))
    }

    // MARK: - deleteRound

    func testDeleteRound() {
        let id = startRound()

        store.deleteRound(id)

        XCTAssertTrue(store.rounds.isEmpty)
    }

    func testDeleteRoundLeavesOtherRounds() {
        startRound()
        startRound()
        XCTAssertEqual(store.rounds.count, 2)

        let roundToDelete = store.rounds[1]
        store.deleteRound(roundToDelete.id)

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertNotEqual(store.rounds[0].id, roundToDelete.id)
    }

    // MARK: - activeRound / currentRound

    func testActiveRoundReturnsNilWhenNoRounds() {
        XCTAssertNil(store.activeRound)
        XCTAssertNil(store.currentRound)
    }

    func testActiveRoundReturnsNilWhenAllEnded() {
        let id = startRound()
        store.update(id) { $0.end(at: Date()) }

        XCTAssertNil(store.activeRound)
        XCTAssertNil(store.currentRound)
    }

    func testActiveRoundReturnsTheActiveOne() {
        let id = startRound()

        XCTAssertEqual(store.activeRound?.id, id)
        XCTAssertEqual(store.currentRound?.id, id)
    }

    func testEndingRoundIsCurrentButNotActive() {
        let id = startRound()
        store.update(id) { $0.status = .ending }

        XCTAssertNil(store.activeRound)
        XCTAssertEqual(store.currentRound?.id, id)
    }

    // MARK: - No handlers set

    func testMutationsWorkWithoutHandlers() {
        store.onTimelineChanged = nil
        store.onMarksChanged = nil

        let id = startRound()
        store.addMark(to: id, holeIndex: 0, mark: makeMark())
        store.startHole(1, source: .autoAdvance)

        // Should not crash
        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertEqual(store.rounds[0].allMarks.count, 1)
        XCTAssertEqual(store.rounds[0].currentHoleIndex, 1)
    }
}

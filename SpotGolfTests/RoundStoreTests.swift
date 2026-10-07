import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

@MainActor
final class RoundStoreTests: XCTestCase {

    private var directory: URL!
    private var store: RoundStore!
    private var timelineChanges: [Round]!
    private var displayHoleChanges: [Round]!
    private var strokeChanges: [Round]!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = RoundStore(directory: directory)
        timelineChanges = []
        displayHoleChanges = []
        strokeChanges = []
        store.onTimelineChanged = { [weak self] round in
            self?.timelineChanges.append(round)
        }
        store.onDisplayHoleChanged = { [weak self] round in
            self?.displayHoleChanges.append(round)
        }
        store.onStrokesChanged = { [weak self] round in
            self?.strokeChanges.append(round)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        timelineChanges = nil
        displayHoleChanges = nil
        strokeChanges = nil
        directory = nil
        super.tearDown()
    }

    private func makeStroke(latitude: Double = 33.45, longitude: Double = -112.07) -> Stroke {
        Stroke(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    /// Starts a round and returns its ID.
    private func startRound() -> UUID {
        store.startRound(courseSelection: .test).id
    }

    // MARK: - Loading

    func testRoundsSurviveNewStoreInstance() {
        let id = startRound()
        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())

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
        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())

        let again = store.startRound(id: id, courseSelection: .test, status: .starting)

        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertEqual(again.status, .active)
        XCTAssertEqual(again.allStrokes.count, 1)
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

    // MARK: - Display hole

    func testSetDisplayHoleReportsChangeAndLeavesTheTimelineAlone() {
        let id = startRound()

        store.setDisplayHole(2)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 2)
        XCTAssertEqual(displayHoleChanges.count, 1)
        XCTAssertEqual(displayHoleChanges[0].displayHoleIndex, 2)
        XCTAssertEqual(store.round(id)?.holeTimeline.count, 1)
        XCTAssertTrue(timelineChanges.isEmpty)
    }

    func testSetDisplayHoleByRoundID() {
        let id = startRound()
        store.update(id) { $0.status = .ending }

        store.setDisplayHole(1, roundID: id)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 1)
    }

    func testSetDisplayHoleToTheSameHoleIsNoOp() {
        let id = startRound()

        store.setDisplayHole(0)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 0)
        XCTAssertTrue(displayHoleChanges.isEmpty)
    }

    func testSetDisplayHoleWithoutActiveRoundIsNoOp() {
        store.setDisplayHole(1)

        XCTAssertTrue(store.rounds.isEmpty)
        XCTAssertTrue(displayHoleChanges.isEmpty)
    }

    func testMergeDisplayHoleDoesNotReportChange() {
        let id = startRound()
        let later = DisplayHole(holeIndex: 4, changedAt: Date().addingTimeInterval(1))

        XCTAssertTrue(store.mergeDisplayHole(later, roundID: id))

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 4)
        XCTAssertTrue(displayHoleChanges.isEmpty)
        XCTAssertFalse(store.mergeDisplayHole(later, roundID: id))
    }

    // MARK: - Pins

    private func pathGreen(_ hole: Int) -> CLLocationCoordinate2D {
        let green = PathCourse.greens[hole]
        return PathCourse.coordinate(north: green.north, east: green.east).clLocation.coordinate
    }

    func testSetPinReportsChange() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        var changes: [Round] = []
        store.onPinsChanged = { changes.append($0) }

        store.setPin(pathGreen(1), holeIndex: 1)

        XCTAssertNotNil(store.round(id)?.pin(onHole: 1))
        XCTAssertEqual(changes.count, 1)
    }

    func testSetPinOffTheGreenIsNoOp() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        var changes: [Round] = []
        store.onPinsChanged = { changes.append($0) }

        store.setPin(pathGreen(0), holeIndex: 1)

        XCTAssertTrue(store.round(id)?.pins.isEmpty == true)
        XCTAssertTrue(changes.isEmpty)
    }

    func testMergePinsDoesNotReportChange() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        var changes: [Round] = []
        store.onPinsChanged = { changes.append($0) }
        let pin = PinLocation(holeIndex: 0, coordinate: pathGreen(0), setAt: Date())

        XCTAssertTrue(store.mergePins([pin], roundID: id))

        XCTAssertEqual(store.round(id)?.pins, [pin])
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(store.mergePins([pin], roundID: id))
    }

    // MARK: - Hole timeline

    func testMergeTimelineDoesNotReportChange() {
        let id = startRound()
        var other = store.round(id)!
        other.startHole(4, at: other.date.addingTimeInterval(600), source: .stroke)

        XCTAssertTrue(store.mergeTimeline(other.holeTimeline, roundID: id))

        XCTAssertEqual(store.round(id)?.holeTimeline.map(\.holeIndex), [0, 4])
        XCTAssertTrue(timelineChanges.isEmpty)
        XCTAssertFalse(store.mergeTimeline(other.holeTimeline, roundID: id))
    }

    func testSetTimelineReportsChangeOnlyWhenDifferent() {
        let id = startRound()
        var round = store.round(id)!
        round.startHole(2, at: round.date.addingTimeInterval(600), source: .estimated)

        store.setTimeline(round.holeTimeline, roundID: id)
        store.setTimeline(round.holeTimeline, roundID: id)

        XCTAssertEqual(store.round(id)?.holeTimeline.last?.holeIndex, 2)
        XCTAssertEqual(timelineChanges.count, 1)
    }

    func testSetStartTimeStaysBetweenNeighbors() throws {
        let id = store.startRound(date: Date().addingTimeInterval(-3600), courseSelection: .test).id
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: Date().addingTimeInterval(-1800))
        store.addStroke(to: id, holeIndex: 2, stroke: makeStroke(), hitAt: Date().addingTimeInterval(-600))
        let timeline = try XCTUnwrap(store.round(id)?.holeTimeline)

        // Before hole 1's start: kept just after it, so no entry is dropped
        store.setStartTime(timeline[0].startedAt.addingTimeInterval(-60), entryID: timeline[2].id, roundID: id)

        let updated = try XCTUnwrap(store.round(id)?.holeTimeline)
        XCTAssertEqual(updated.map(\.holeIndex), [0, 1, 2])
        XCTAssertEqual(updated[2].startedAt, timeline[1].startedAt.addingTimeInterval(1))
    }

    func testSetStartTimeStrokesEntryUserSet() throws {
        let id = store.startRound(date: Date().addingTimeInterval(-3600), courseSelection: .test).id
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: Date())
        let entry = try XCTUnwrap(store.round(id)?.holeTimeline.last)
        let newTime = entry.startedAt.addingTimeInterval(-30)

        store.setStartTime(newTime, entryID: entry.id, roundID: id)

        let updated = try XCTUnwrap(store.round(id)?.holeTimeline.last)
        XCTAssertEqual(updated.startedAt, newTime)
        XCTAssertEqual(updated.source, .userSet)
        XCTAssertEqual(updated.version, entry.version + 1)
    }

    // MARK: - addStroke

    func testAddStrokeToSpecificRound() {
        let id = startRound()
        let stroke = makeStroke()

        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        XCTAssertEqual(store.round(id)?.displayHoleStrokes.count, 1)
        XCTAssertEqual(store.round(id)?.displayHoleStrokes[0].id, stroke.id)
    }

    func testAddStrokeBumpsVersionAndReportsChange() {
        let id = startRound()

        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())

        XCTAssertEqual(store.round(id)?.strokesVersion, 1)
        XCTAssertEqual(strokeChanges.count, 1)
        XCTAssertEqual(strokeChanges[0].strokesVersion, 1)
    }

    func testAddDuplicateStrokeDoesNotBumpVersion() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        XCTAssertEqual(store.round(id)?.strokesVersion, 1)
        XCTAssertEqual(strokeChanges.count, 1)
    }

    func testAddStrokeToNonexistentRoundIsNoOp() {
        store.addStroke(to: UUID(), holeIndex: 0, stroke: makeStroke())

        XCTAssertTrue(store.rounds.isEmpty)
        XCTAssertTrue(strokeChanges.isEmpty)
    }

    func testAddStrokeToSpecificHoleIndex() {
        let id = startRound()
        let stroke = makeStroke()

        store.addStroke(to: id, holeIndex: 2, stroke: stroke)

        XCTAssertEqual(store.round(id)?.holes.count, 3)
        XCTAssertEqual(store.round(id)?.holes[2].strokes.first?.id, stroke.id)
    }

    func testAddStrokeWithItsTimeStartsTheHole() {
        let id = startRound()
        let hitAt = Date().addingTimeInterval(600)

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: hitAt)

        XCTAssertEqual(store.round(id)?.holeTimeline.map(\.holeIndex), [0, 1])
        XCTAssertEqual(store.round(id)?.holeTimeline.last?.startedAt, hitAt)
        XCTAssertEqual(store.round(id)?.holeTimeline.last?.source, .stroke)
        XCTAssertEqual(timelineChanges.count, 1)
        XCTAssertEqual(strokeChanges.count, 1)
    }

    func testAddStrokeWithoutItsTimeLeavesTheTimelineAlone() {
        let id = startRound()

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke())

        XCTAssertEqual(store.round(id)?.holeTimeline.count, 1)
        XCTAssertTrue(timelineChanges.isEmpty)
    }

    func testLaterStrokeOnAHoleKeepsItsStart() {
        let id = startRound()
        let first = Date().addingTimeInterval(600)
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: first)

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: first.addingTimeInterval(60))

        XCTAssertEqual(store.round(id)?.holeTimeline.last?.startedAt, first)
        XCTAssertEqual(timelineChanges.count, 1)
    }

    func testEarlierStrokeOnAHoleMovesItsStartBack() {
        let id = startRound()
        let first = Date().addingTimeInterval(600)
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: first)

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: first.addingTimeInterval(-60))

        XCTAssertEqual(store.round(id)?.holeTimeline.last?.startedAt, first.addingTimeInterval(-60))
        XCTAssertEqual(store.round(id)?.holeTimeline.last?.version, 1)
        XCTAssertEqual(timelineChanges.count, 2)
    }

    func testAddingAStrokeAgainDoesNotTouchTheTimeline() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 1, stroke: stroke, hitAt: Date().addingTimeInterval(600))

        store.addStroke(to: id, holeIndex: 1, stroke: stroke, hitAt: Date().addingTimeInterval(300))

        XCTAssertEqual(timelineChanges.count, 1)
    }

    // MARK: - moveStroke

    func testMoveStroke() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].latitude, 34.0)
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].longitude, -113.0)
        // ID should be preserved
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].id, stroke.id)
    }

    func testMoveStrokeAcrossHoles() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)
        store.setDisplayHole(1)

        // Stroke is in hole 0, but we're on hole 1 — should still find it
        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].holes[0].strokes[0].latitude, 34.0)
    }

    func testMoveStrokeBumpsVersion() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)
        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 35.0, longitude: -114.0), in: id)

        XCTAssertEqual(store.round(id)?.strokesVersion, 3)
        XCTAssertEqual(strokeChanges.map(\.strokesVersion), [1, 2, 3])
    }

    // MARK: - reorderStroke

    func testReorderStroke() {
        let id = startRound()
        let stroke0 = makeStroke(latitude: 33.0, longitude: -112.0)
        let stroke1 = makeStroke(latitude: 34.0, longitude: -113.0)
        let stroke2 = makeStroke(latitude: 35.0, longitude: -114.0)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke0)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke1)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke2)

        // Move stroke2 from index 2 to index 0
        store.reorderStroke(stroke2, to: 0, in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].id, stroke2.id)
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[1].id, stroke0.id)
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[2].id, stroke1.id)
        XCTAssertEqual(store.round(id)?.strokesVersion, 4)
    }

    func testReorderStrokeClampsToValidRange() {
        let id = startRound()
        let stroke0 = makeStroke(latitude: 33.0, longitude: -112.0)
        let stroke1 = makeStroke(latitude: 34.0, longitude: -113.0)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke0)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke1)

        // Try to move to an out-of-bounds index
        store.reorderStroke(stroke0, to: 100, in: id)

        // Should be clamped to last index
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[1].id, stroke0.id)
    }

    func testReorderStrokeClampsNegativeIndex() {
        let id = startRound()
        let stroke0 = makeStroke(latitude: 33.0, longitude: -112.0)
        let stroke1 = makeStroke(latitude: 34.0, longitude: -113.0)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke0)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke1)

        store.reorderStroke(stroke1, to: -5, in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].id, stroke1.id)
    }

    func testReorderToSamePlaceDoesNotBumpVersion() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.reorderStroke(stroke, to: 0, in: id)

        XCTAssertEqual(store.round(id)?.strokesVersion, 1)
    }

    // MARK: - removeStroke

    func testRemoveStroke() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.removeStroke(stroke, from: id)

        XCTAssertTrue(store.rounds[0].displayHoleStrokes.isEmpty)
        XCTAssertEqual(store.round(id)?.strokesVersion, 2)
        XCTAssertEqual(strokeChanges.count, 2)
    }

    func testRemoveStrokeLeavesOtherStrokes() {
        let id = startRound()
        let stroke1 = makeStroke(latitude: 33.0, longitude: -112.0)
        let stroke2 = makeStroke(latitude: 34.0, longitude: -113.0)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke1)
        store.addStroke(to: id, holeIndex: 0, stroke: stroke2)

        store.removeStroke(stroke1, from: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes.count, 1)
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].id, stroke2.id)
    }

    func testRemoveStrokeAcrossHoles() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)
        store.setDisplayHole(1)

        // Stroke is in hole 0, we're on hole 1
        store.removeStroke(stroke, from: id)

        XCTAssertTrue(store.rounds[0].holes[0].strokes.isEmpty)
    }

    func testRemoveMissingStrokeDoesNotBumpVersion() {
        let id = startRound()

        store.removeStroke(makeStroke(), from: id)

        XCTAssertEqual(store.round(id)?.strokesVersion, 0)
        XCTAssertTrue(strokeChanges.isEmpty)
    }

    // MARK: - setStrokeType

    func testSetStrokeType() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.setStrokeType(strokeID: stroke.id, type: .penalty, in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].type, .penalty)
        XCTAssertEqual(strokeChanges.last?.displayHoleStrokes[0].type, .penalty)
    }

    func testSetStrokeTypeToOutOfBounds() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.setStrokeType(strokeID: stroke.id, type: .outOfBounds, in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].type, .outOfBounds)
    }

    func testSetStrokeTypeBackToRegular() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)
        store.setStrokeType(strokeID: stroke.id, type: .penalty, in: id)

        store.setStrokeType(strokeID: stroke.id, type: .regular, in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].type, .regular)
    }

    func testMoveStrokePreservesType() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)
        store.setStrokeType(strokeID: stroke.id, type: .penalty, in: id)

        store.moveStroke(store.rounds[0].displayHoleStrokes[0], to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].type, .penalty)
    }

    // MARK: - Editing a past round

    /// Starts a round with one stroke on each of the first two holes, then ends it.
    private func endedRound() -> (id: UUID, first: Stroke, second: Stroke) {
        let id = startRound()
        let first = makeStroke()
        let second = makeStroke(latitude: 33.46)
        store.addStroke(to: id, holeIndex: 0, stroke: first)
        store.addStroke(to: id, holeIndex: 1, stroke: second)
        store.update(id) { $0.status = .ended }
        strokeChanges.removeAll()
        return (id, first, second)
    }

    func testAddStrokeToEndedRound() {
        let (id, _, _) = endedRound()
        let stroke = makeStroke(latitude: 33.47)

        store.addStroke(to: id, holeIndex: 2, stroke: stroke)

        XCTAssertEqual(store.round(id)?.holes[2].strokes, [stroke])
        XCTAssertEqual(store.round(id)?.status, .ended)
        XCTAssertEqual(strokeChanges.count, 1)
    }

    func testMoveStrokeInEndedRound() {
        let (id, first, _) = endedRound()
        let coordinate = CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0)

        store.moveStroke(first, to: coordinate, in: id)

        XCTAssertEqual(store.round(id)?.holes[0].strokes[0].coordinate.latitude, 34.0)
        XCTAssertEqual(strokeChanges.count, 1)
    }

    func testReorderStrokeInEndedRound() {
        let (id, first, _) = endedRound()
        let added = makeStroke(latitude: 33.48)
        store.addStroke(to: id, holeIndex: 0, stroke: added)

        store.reorderStroke(first, to: 1, in: id)

        XCTAssertEqual(store.round(id)?.holes[0].strokes.map(\.id), [added.id, first.id])
    }

    func testSetStrokeTypeInEndedRound() {
        let (id, _, second) = endedRound()

        store.setStrokeType(strokeID: second.id, type: .outOfBounds, in: id)

        XCTAssertEqual(store.round(id)?.holes[1].strokes[0].type, .outOfBounds)
        XCTAssertEqual(strokeChanges.count, 1)
    }

    func testRemoveStrokeFromEndedRound() {
        let (id, first, second) = endedRound()

        store.removeStroke(first, from: id)

        XCTAssertEqual(store.round(id)?.holes[0].strokes, [])
        XCTAssertEqual(store.round(id)?.holes[1].strokes, [second])
        XCTAssertEqual(strokeChanges.count, 1)
    }

    func testEndedRoundEditsSurviveNewStoreInstance() {
        let (id, first, _) = endedRound()
        store.setStrokeType(strokeID: first.id, type: .penalty, in: id)

        let reloaded = RoundStore(directory: directory)

        XCTAssertEqual(reloaded.round(id)?.holes[0].strokes[0].type, .penalty)
        XCTAssertEqual(reloaded.round(id)?.status, .ended)
    }

    // MARK: - applyStrokes

    func testApplyStrokesReplacesStrokesWhenNewer() {
        let id = startRound()
        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())
        let replacement = makeStroke(latitude: 34.0, longitude: -113.0)
        strokeChanges.removeAll()

        XCTAssertTrue(store.applyStrokes(StrokesSnapshot(roundID: id, version: 5, holes: [[], [replacement]])))

        XCTAssertEqual(store.round(id)?.strokesVersion, 5)
        XCTAssertEqual(store.round(id)?.holes.map(\.strokes), [[], [replacement]])
        XCTAssertTrue(strokeChanges.isEmpty)
    }

    func testApplyStrokesIgnoresOlderOrSameVersion() {
        let id = startRound()
        let newer = makeStroke(latitude: 34.0, longitude: -113.0)
        store.applyStrokes(StrokesSnapshot(roundID: id, version: 6, holes: [[newer]]))

        XCTAssertFalse(store.applyStrokes(StrokesSnapshot(roundID: id, version: 5, holes: [[makeStroke()]])))
        XCTAssertFalse(store.applyStrokes(StrokesSnapshot(roundID: id, version: 6, holes: [])))

        XCTAssertEqual(store.round(id)?.displayHoleStrokes, [newer])
    }

    func testApplyEmptyStrokesKeepsOneHole() {
        let id = startRound()

        store.applyStrokes(StrokesSnapshot(roundID: id, version: 1, holes: []))

        XCTAssertEqual(store.round(id)?.holes.count, 1)
    }

    func testApplyStrokesForUnknownRoundIsIgnored() {
        XCTAssertFalse(store.applyStrokes(StrokesSnapshot(roundID: UUID(), version: 1, holes: [])))
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
        store.onDisplayHoleChanged = nil
        store.onStrokesChanged = nil

        let id = startRound()
        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(), hitAt: Date().addingTimeInterval(600))
        store.setDisplayHole(1)

        // Should not crash
        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertEqual(store.rounds[0].allStrokes.count, 2)
        XCTAssertEqual(store.rounds[0].holeTimeline.map(\.holeIndex), [0, 1])
        XCTAssertEqual(store.rounds[0].displayHoleIndex, 1)
    }
}

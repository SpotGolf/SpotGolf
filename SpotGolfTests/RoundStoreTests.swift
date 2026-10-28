import SwiftData
import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

@MainActor
final class RoundStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var store: RoundStore!
    private var displayHoleChanges: [Round]!
    private var strokeChanges: [Round]!
    /// The round's strokes version when each stroke change was reported.
    private var strokeVersions: [Int]!

    override func setUp() async throws {
        try await super.setUp()
        container = Storage.inMemoryContainer()
        store = RoundStore(context: ModelContext(container))
        displayHoleChanges = []
        strokeChanges = []
        strokeVersions = []
        store.addListener { [weak self] event in
            switch event {
            case .displayHoleChanged(let round): self?.displayHoleChanges.append(round)
            case .strokesChanged(let round):
                self?.strokeChanges.append(round)
                self?.strokeVersions.append(round.strokesVersion)
            case .pinsChanged, .roundsChanged, .roundDeleted: break
            }
        }
    }

    override func tearDown() async throws {
        store = nil
        displayHoleChanges = nil
        strokeChanges = nil
        strokeVersions = nil
        container = nil
        try await super.tearDown()
    }

    private func makeStroke(latitude: Double = 33.45, longitude: Double = -112.07, origin: StrokeOrigin = .manual,
                            hitAt: Date? = nil) -> Stroke {
        Stroke(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), origin: origin, hitAt: hitAt)
    }

    /// Starts a round and returns its ID.
    private func startRound() -> UUID {
        store.startRound(courseSelection: .test).id
    }

    // MARK: - Loading

    func testRoundsSurviveNewStoreInstance() {
        let id = startRound()
        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())

        let reloaded = RoundStore(context: ModelContext(container))

        XCTAssertEqual(reloaded.rounds.map(\.id), store.rounds.map(\.id))
        XCTAssertEqual(reloaded.round(id)?.allStrokes, store.round(id)?.allStrokes)
    }

    // MARK: - Clubs

    func testSetStrokeClubChangesTheClubAndMoveStrokeKeepsIt() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)
        XCTAssertNil(store.round(id)?.holes[0].strokes[0].club)

        store.setStrokeClub(strokeID: stroke.id, club: Club.named("7i"), in: id)
        XCTAssertEqual(store.round(id)?.holes[0].strokes[0].club?.id, "7i")

        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 33.46, longitude: -112.08), in: id)
        let moved = store.round(id)?.holes[0].strokes[0]
        XCTAssertEqual(moved?.latitude, 33.46)
        XCTAssertEqual(moved?.club?.id, "7i", "Moving a stroke keeps its club")

        store.setStrokeClub(strokeID: stroke.id, club: nil, in: id)
        XCTAssertNil(store.round(id)?.holes[0].strokes[0].club)
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
        XCTAssertEqual(store.round(id)?.startedHoles, [0])
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
        store.addListener { if case .pinsChanged(let round) = $0 { changes.append(round) } }

        store.setPin(pathGreen(1), holeIndex: 1)

        XCTAssertNotNil(store.round(id)?.pin(onHole: 1))
        XCTAssertEqual(changes.count, 1)
    }

    func testSetPinOffTheGreenIsNoOp() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        var changes: [Round] = []
        store.addListener { if case .pinsChanged(let round) = $0 { changes.append(round) } }

        store.setPin(pathGreen(0), holeIndex: 1)

        XCTAssertEqual(store.round(id)?.pins, [nil, nil, nil])
        XCTAssertTrue(changes.isEmpty)
    }

    func testMergePinsDoesNotReportChange() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        var changes: [Round] = []
        store.addListener { if case .pinsChanged(let round) = $0 { changes.append(round) } }
        let pin = PinLocation(coordinate: pathGreen(0), setAt: Date())

        XCTAssertTrue(store.mergePins([pin], roundID: id))

        XCTAssertEqual(store.round(id)?.pins, [pin, nil, nil])
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(store.mergePins([pin], roundID: id))
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

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: hitAt))

        XCTAssertEqual(store.round(id)?.startedHoles, [0, 1])
        XCTAssertEqual(store.round(id)?.startOfHole(1), hitAt)
        XCTAssertEqual(strokeChanges.count, 1)
    }

    func testAddStrokeWithoutItsTimeLeavesTheTimelineAlone() {
        let id = startRound()

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke())

        XCTAssertEqual(store.round(id)?.startedHoles, [0])
    }

    func testLaterStrokeOnAHoleKeepsItsStart() {
        let id = startRound()
        let first = Date().addingTimeInterval(600)
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: first))

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: first.addingTimeInterval(60)))

        XCTAssertEqual(store.round(id)?.startOfHole(1), first)
    }

    func testEarlierStrokeOnAHoleMovesItsStartBack() {
        let id = startRound()
        let first = Date().addingTimeInterval(600)
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: first))

        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: first.addingTimeInterval(-60)))

        XCTAssertEqual(store.round(id)?.startOfHole(1), first.addingTimeInterval(-60))
    }

    func testAddingAStrokeAgainDoesNotTouchTheTimeline() {
        let id = startRound()
        let first = Date().addingTimeInterval(600)
        var stroke = makeStroke(hitAt: first)
        store.addStroke(to: id, holeIndex: 1, stroke: stroke)

        stroke.hitAt = Date().addingTimeInterval(300)
        store.addStroke(to: id, holeIndex: 1, stroke: stroke)

        XCTAssertEqual(store.round(id)?.startOfHole(1), first)
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
        XCTAssertEqual(strokeVersions, [1, 2, 3])
    }

    func testMovingAManualStrokeMovesItsHolesStartBothWays() {
        let id = startRound()
        let start = Date().addingTimeInterval(600)
        let stroke = makeStroke(hitAt: start)
        store.addStroke(to: id, holeIndex: 1, stroke: stroke)

        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id) { _ in
            start.addingTimeInterval(-120)
        }
        XCTAssertEqual(store.round(id)?.startOfHole(1), start.addingTimeInterval(-120))
        XCTAssertEqual(store.round(id)?.holes[1].strokes[0].hitAt, start.addingTimeInterval(-120))

        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 35.0, longitude: -114.0), in: id) { _ in
            start.addingTimeInterval(60)
        }
        XCTAssertEqual(store.round(id)?.startOfHole(1), start.addingTimeInterval(60))
    }

    func testMovingASuggestionStrokeKeepsItsTimeAndItsHolesStart() {
        let id = startRound()
        let start = Date().addingTimeInterval(600)
        let stroke = makeStroke(origin: .suggestion(id: UUID()), hitAt: start)
        store.addStroke(to: id, holeIndex: 1, stroke: stroke)

        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id) { _ in
            start.addingTimeInterval(-120)
        }

        let moved = store.round(id)?.holes[1].strokes[0]
        XCTAssertEqual(moved?.latitude, 34.0)
        XCTAssertEqual(moved?.hitAt, start)
        XCTAssertEqual(moved?.origin, stroke.origin)
        XCTAssertEqual(store.round(id)?.startOfHole(1), start)
    }

    func testMovingAStrokeKeepsItsOtherValues() {
        let id = startRound()
        var stroke = makeStroke(hitAt: Date())
        stroke.penaltyStrokes = 2
        stroke.quality = .bad
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        let moved = store.round(id)?.holes[0].strokes[0]
        XCTAssertEqual(moved?.penaltyStrokes, 2)
        XCTAssertEqual(moved?.quality, .bad)
        XCTAssertEqual(moved?.origin, .manual)
        XCTAssertNil(moved?.hitAt, "No GPS to time it at its new spot")
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

    func testRemovingAHolesLastStrokeClearsItsStart() {
        let id = startRound()
        let stroke = makeStroke(hitAt: Date().addingTimeInterval(600))
        store.addStroke(to: id, holeIndex: 1, stroke: stroke)

        store.removeStroke(stroke, from: id)

        XCTAssertNil(store.round(id)?.startOfHole(1))
        XCTAssertEqual(store.round(id)?.startedHoles, [0])
    }

    func testRemovingTheEarliestStrokeMovesItsHolesStartLater() {
        let id = startRound()
        let start = Date().addingTimeInterval(600)
        let first = makeStroke(hitAt: start)
        store.addStroke(to: id, holeIndex: 1, stroke: first)
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: start.addingTimeInterval(180)))

        store.removeStroke(first, from: id)

        XCTAssertEqual(store.round(id)?.startOfHole(1), start.addingTimeInterval(180))
    }

    func testRemovingAStrokeTimesAManualStrokeWithNoTimeFromTheGPS() {
        let id = startRound()
        let start = Date().addingTimeInterval(600)
        let first = makeStroke(hitAt: start)
        store.addStroke(to: id, holeIndex: 1, stroke: first)
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke())

        store.removeStroke(first, from: id) { _ in start.addingTimeInterval(240) }

        XCTAssertEqual(store.round(id)?.startOfHole(1), start.addingTimeInterval(240))
        XCTAssertNil(store.round(id)?.holes[1].strokes[0].hitAt, "The estimate is not saved")
    }

    func testRemovingAStrokeAddedToTheWrongHoleGivesTheHoleBack() throws {
        let id = startRound()
        let holeOneStart = Date().addingTimeInterval(600)
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: holeOneStart))
        // Hole 1's tee shot added to hole 2 by mistake
        let mistake = makeStroke(hitAt: holeOneStart.addingTimeInterval(30))
        store.addStroke(to: id, holeIndex: 2, stroke: mistake)
        let round = try XCTUnwrap(store.round(id))
        XCTAssertFalse(round.possibleHoles(at: holeOneStart.addingTimeInterval(300)).contains(1))

        store.removeStroke(mistake, from: id)

        XCTAssertNil(round.startOfHole(2))
        XCTAssertTrue(round.possibleHoles(at: holeOneStart.addingTimeInterval(300)).contains(1))
    }

    func testRemoveMissingStrokeDoesNotBumpVersion() {
        let id = startRound()

        store.removeStroke(makeStroke(), from: id)

        XCTAssertEqual(store.round(id)?.strokesVersion, 0)
        XCTAssertTrue(strokeChanges.isEmpty)
    }

    // MARK: - setPenaltyStrokes

    func testSetPenaltyStrokes() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.setPenaltyStrokes(2, strokeID: stroke.id, in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].penaltyStrokes, 2)
        XCTAssertEqual(strokeChanges.last?.displayHoleStrokes[0].penaltyStrokes, 2)
    }

    func testSetPenaltyStrokesStaysBetweenZeroAndTheMost() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.setPenaltyStrokes(7, strokeID: stroke.id, in: id)
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].penaltyStrokes, Stroke.maxPenaltyStrokes)

        store.setPenaltyStrokes(-1, strokeID: stroke.id, in: id)
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].penaltyStrokes, 0)
    }

    func testSetShotQuality() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)

        store.setShotQuality(.bad, strokeID: stroke.id, in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].quality, .bad)
        XCTAssertEqual(strokeChanges.last?.displayHoleStrokes[0].quality, .bad)
    }

    func testMoveStrokePreservesPenaltyStrokesAndQuality() {
        let id = startRound()
        let stroke = makeStroke()
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)
        store.setPenaltyStrokes(1, strokeID: stroke.id, in: id)
        store.setShotQuality(.okay, strokeID: stroke.id, in: id)

        store.moveStroke(store.rounds[0].displayHoleStrokes[0], to: CLLocationCoordinate2D(latitude: 34.0, longitude: -113.0), in: id)

        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].penaltyStrokes, 1)
        XCTAssertEqual(store.rounds[0].displayHoleStrokes[0].quality, .okay)
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

    func testSetPenaltyStrokesInEndedRound() {
        let (id, _, second) = endedRound()

        store.setPenaltyStrokes(1, strokeID: second.id, in: id)

        XCTAssertEqual(store.round(id)?.holes[1].strokes[0].penaltyStrokes, 1)
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
        store.setPenaltyStrokes(1, strokeID: first.id, in: id)

        let reloaded = RoundStore(context: ModelContext(container))

        XCTAssertEqual(reloaded.round(id)?.holes[0].strokes[0].penaltyStrokes, 1)
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

    func testDeleteRoundReportsIt() {
        let id = startRound()
        var deleted: [UUID] = []
        store.addListener { event in
            if case .roundDeleted(let roundID) = event { deleted.append(roundID) }
        }

        store.deleteRound(id)
        store.deleteRound(id)

        XCTAssertEqual(deleted, [id], "Only a round that was there")
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

    // MARK: - No listeners

    func testMutationsWorkWithoutListeners() {
        store = RoundStore(context: ModelContext(container))

        let id = startRound()
        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())
        store.addStroke(to: id, holeIndex: 1, stroke: makeStroke(hitAt: Date().addingTimeInterval(600)))
        store.setDisplayHole(1)

        // Should not crash
        XCTAssertEqual(store.rounds.count, 1)
        XCTAssertEqual(store.rounds[0].allStrokes.count, 2)
        XCTAssertEqual(store.rounds[0].startedHoles, [0, 1])
        XCTAssertEqual(store.rounds[0].displayHoleIndex, 1)
    }

    // MARK: - Listeners

    func testListenersRunDuringTheChangeInOrder() {
        var calls: [String] = []
        store.addListener { if case .strokesChanged = $0 { calls.append("first") } }
        store.addListener { if case .strokesChanged = $0 { calls.append("second") } }
        let id = startRound()

        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())

        XCTAssertEqual(calls, ["first", "second"])
    }

    func testChangeFromOtherDeviceIsOnlyRoundsChanged() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        var events: [RoundEvent] = []
        store.addListener { events.append($0) }
        let pin = PinLocation(coordinate: pathGreen(0), setAt: Date())

        XCTAssertTrue(store.mergePins([pin], roundID: id))

        XCTAssertEqual(events.count, 1)
        guard case .roundsChanged = events.first else {
            return XCTFail("Expected roundsChanged, got \(String(describing: events.first))")
        }
    }

    // MARK: - Taken suggestions

    func testASuggestionIsHiddenWhileItsStrokeExists() {
        let id = startRound()
        let suggestionID = UUID()
        let stroke = makeStroke(origin: .suggestion(id: suggestionID), hitAt: Date())
        store.addStroke(to: id, holeIndex: 0, stroke: stroke)
        store.addStroke(to: id, holeIndex: 0, stroke: makeStroke())

        XCTAssertEqual(RoundStore(context: ModelContext(container)).round(id)?.takenSuggestionIDs, [suggestionID])

        store.removeStroke(stroke, from: id)

        XCTAssertEqual(store.round(id)?.takenSuggestionIDs, [])
    }
}

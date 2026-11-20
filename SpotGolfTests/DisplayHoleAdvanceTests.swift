import CoreLocation
import SwiftData
import XCTest
@testable import SpotGolf

/// The phone's display hole moving on from the watch's fixes. The advancer's own rules are
/// tested in `HoleAdvancerTests`; standing on the next tee is the simplest of them.
@MainActor
final class DisplayHoleAdvanceTests: XCTestCase {
    private var container: ModelContainer!
    private var store: RoundStore!
    private var advance: DisplayHoleAdvance!
    /// The phone's clock.
    private var now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        container = Storage.inMemoryContainer()
        store = RoundStore(context: ModelContext(container))
        advance = DisplayHoleAdvance(rounds: store) { [unowned self] in self.now }
    }

    override func tearDown() async throws {
        advance = nil
        store = nil
        container = nil
        try await super.tearDown()
    }

    /// A fix on hole `hole`'s tee.
    private func onTee(_ hole: Int, second: TimeInterval = 0) -> TrackPoint {
        let tee = PathCourse.coordinate(north: PathCourse.tees[hole].north, east: PathCourse.tees[hole].east)
        return TrackPoint(timestamp: now.addingTimeInterval(second), latitude: tee.lat, longitude: tee.lon, altitude: nil)
    }

    func testAFixOnTheNextTeeMovesTheDisplayHoleOn() {
        let id = store.startRound(courseSelection: PathCourse.selection).id

        advance.received([onTee(1)], roundID: id)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 1)
        XCTAssertEqual(store.round(id)?.playingHoleIndex, 0)
    }

    func testABatchMovesTheHoleOnOncePerTee() {
        let id = store.startRound(courseSelection: PathCourse.selection).id

        advance.received([onTee(1), onTee(1, second: 1), onTee(2, second: 600)], roundID: id)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 2)
    }

    func testOnlyTheHoleAfterTheOneShownIsChecked() {
        let id = store.startRound(courseSelection: PathCourse.selection).id

        advance.received([onTee(2)], roundID: id)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 0)
    }

    func testAPickedHoleIsHeldForTheHoldTimeThenMovesOn() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        store.setDisplayHole(1, roundID: id, at: now, holds: true)

        // On hole 3's tee while the pick is held
        now += DisplayHole.holdTime - 1
        advance.received([onTee(2)], roundID: id)
        XCTAssertEqual(store.round(id)?.displayHoleIndex, 1)

        // Still there once the hold is over
        now += 1
        advance.received([onTee(2, second: DisplayHole.holdTime)], roundID: id)
        XCTAssertEqual(store.round(id)?.displayHoleIndex, 2)
    }

    /// The hold is the user's, on the phone's clock: old fixes that arrive during it do not get past it.
    func testLateFixesDoNotGetPastAHold() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        store.holdDisplayHole(roundID: id, at: now)

        advance.received([onTee(1, second: -600)], roundID: id)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 0)
    }

    func testARoundThatIsNotActiveStaysOnItsHole() {
        let id = store.startRound(courseSelection: PathCourse.selection).id
        store.update(id) { $0.status = .ending }

        advance.received([onTee(1)], roundID: id)

        XCTAssertEqual(store.round(id)?.displayHoleIndex, 0)
    }

    func testAnUnknownRoundIsIgnored() {
        advance.received([onTee(1)], roundID: UUID())

        XCTAssertTrue(store.rounds.isEmpty)
    }
}

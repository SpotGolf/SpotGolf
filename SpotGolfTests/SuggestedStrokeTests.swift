import CoreLocation
import SwiftData
import XCTest
@testable import SpotGolf

@MainActor
final class SuggestedStrokeTests: XCTestCase {

    private var store: RoundStore!

    override func setUp() async throws {
        try await super.setUp()
        store = RoundStore(context: ModelContext(Storage.inMemoryContainer()))
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    /// The player walks north along hole 1, one meter a second.
    private var track: [TrackPoint] {
        (0..<300).map { second in
            let spot = PathCourse.coordinate(north: Double(second), east: 0)
            return TrackPoint(location: CLLocation(coordinate: spot.clLocation.coordinate, altitude: 0,
                                                   horizontalAccuracy: 5, verticalAccuracy: -1,
                                                   timestamp: StreamFixtures.start.addingTimeInterval(TimeInterval(second))))
        }
    }

    private func stroke(north: Double) -> Stroke {
        Stroke(coordinate: PathCourse.coordinate(north: north, east: 0).clLocation.coordinate)
    }

    private func suggestion(north: Double, second: TimeInterval) -> StrokeSuggestion {
        StrokeSuggestion(timestamp: StreamFixtures.start.addingTimeInterval(second), kind: .stop(duration: 30),
                         coordinate: PathCourse.coordinate(north: north, east: 0).clLocation.coordinate)
    }

    func testSuggestionGoesBeforeTheFirstStrokeHitLater() {
        let id = store.startRound(date: StreamFixtures.start, courseSelection: PathCourse.selection).id
        let first = stroke(north: 0)
        let last = stroke(north: 200)
        store.addStroke(to: id, holeIndex: 0, stroke: first)
        store.addStroke(to: id, holeIndex: 0, stroke: last)
        let middle = suggestion(north: 100, second: 100)

        let added = store.addSuggestedStroke(middle, holeIndex: 0, roundID: id, holeTrack: track, bag: .standard)

        let strokes = store.round(id)?.hole(at: 0).strokes ?? []
        XCTAssertEqual(strokes.count, 3)
        XCTAssertEqual(strokes.first?.id, first.id)
        XCTAssertEqual(strokes.last?.id, last.id)
        XCTAssertEqual(strokes[1].id, added?.id)
        XCTAssertEqual(strokes[1].club?.id, "3w", "200 m to the green as the second stroke: the 3 wood, not the driver")
        XCTAssertEqual(strokes[1].origin, .suggestion(id: middle.id))
        XCTAssertEqual(strokes[1].hitAt, middle.timestamp)
        XCTAssertEqual(store.round(id)?.takenSuggestionIDs, [middle.id])
    }

    func testSuggestionHitAfterEveryStrokeGoesLast() {
        let id = store.startRound(date: StreamFixtures.start, courseSelection: PathCourse.selection).id
        let first = stroke(north: 0)
        store.addStroke(to: id, holeIndex: 0, stroke: first)

        store.addSuggestedStroke(suggestion(north: 250, second: 250), holeIndex: 0, roundID: id, holeTrack: track, bag: .standard)

        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.first?.id, first.id)
        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.count, 2)
        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.last?.club?.id, "lw", "50 m from the green is a chip")
    }
}

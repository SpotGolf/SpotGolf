import CoreLocation
import SwiftData
import XCTest
@testable import SpotGolf

@MainActor
final class SuggestedStrokeTests: XCTestCase {

    private var store: RoundStore!

    override func setUp() {
        super.setUp()
        store = RoundStore(context: ModelContext(Storage.inMemoryContainer()))
    }

    override func tearDown() {
        store = nil
        super.tearDown()
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

        store.addSuggestedStroke(middle, holeIndex: 0, roundID: id, holeTrack: track)

        let strokes = store.round(id)?.hole(at: 0).strokes ?? []
        XCTAssertEqual(strokes.count, 3)
        XCTAssertEqual(strokes.first?.id, first.id)
        XCTAssertEqual(strokes.last?.id, last.id)
        XCTAssertEqual(store.round(id)?.hiddenSuggestionIDs, [middle.id])
    }

    func testSuggestionHitAfterEveryStrokeGoesLast() {
        let id = store.startRound(date: StreamFixtures.start, courseSelection: PathCourse.selection).id
        let first = stroke(north: 0)
        store.addStroke(to: id, holeIndex: 0, stroke: first)

        store.addSuggestedStroke(suggestion(north: 250, second: 250), holeIndex: 0, roundID: id, holeTrack: track)

        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.first?.id, first.id)
        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.count, 2)
    }
}

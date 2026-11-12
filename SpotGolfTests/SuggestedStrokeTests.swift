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

    private func stroke(north: Double) -> Stroke {
        Stroke(coordinate: PathCourse.coordinate(north: north, east: 0).clLocation.coordinate)
    }

    private func suggestion(north: Double, second: TimeInterval) -> StrokeSuggestion {
        StrokeSuggestion(timestamp: StreamFixtures.start.addingTimeInterval(second), kind: .stop(duration: 30),
                         coordinate: PathCourse.coordinate(north: north, east: 0).clLocation.coordinate)
    }

    func testSuggestionGoesAfterStrokesFartherAlongTheHole() {
        let id = store.startRound(date: StreamFixtures.start, courseSelection: PathCourse.selection).id
        let first = stroke(north: 0)
        // Over the green, which is 300 m north of the tee
        let over = stroke(north: 320)
        store.addStroke(to: id, holeIndex: 0, stroke: first)
        store.addStroke(to: id, holeIndex: 0, stroke: over)
        // The chip went back over the green, towards the tee
        let back = suggestion(north: 280, second: 400)

        let added = store.addSuggestedStroke(back, holeIndex: 0, roundID: id, bag: .standard)

        let strokes = store.round(id)?.hole(at: 0).strokes ?? []
        XCTAssertEqual(strokes.map(\.id), [first.id, over.id] + [added?.id].compactMap { $0 })
        XCTAssertEqual(strokes[2].origin, .suggestion(id: back.id))
        XCTAssertEqual(strokes[2].hitAt, back.timestamp)
        XCTAssertEqual(store.round(id)?.takenSuggestionIDs, [back.id])
    }

    func testSuggestionHitBeforeAStrokeStillGoesLast() {
        let id = store.startRound(date: StreamFixtures.start, courseSelection: PathCourse.selection).id
        var later = stroke(north: 200)
        later.hitAt = StreamFixtures.start.addingTimeInterval(200)
        store.addStroke(to: id, holeIndex: 0, stroke: later)

        let added = store.addSuggestedStroke(suggestion(north: 100, second: 100), holeIndex: 0, roundID: id, bag: .standard)

        // Taken out of order: the spot sheet's selector puts it right
        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.map(\.id), [later.id] + [added?.id].compactMap { $0 })
    }

    func testSuggestionHitAfterEveryStrokeGoesLast() {
        let id = store.startRound(date: StreamFixtures.start, courseSelection: PathCourse.selection).id
        let first = stroke(north: 0)
        store.addStroke(to: id, holeIndex: 0, stroke: first)

        store.addSuggestedStroke(suggestion(north: 250, second: 250), holeIndex: 0, roundID: id, bag: .standard)

        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.first?.id, first.id)
        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.count, 2)
        XCTAssertEqual(store.round(id)?.hole(at: 0).strokes.last?.club?.id, "lw", "50 m from the green is a chip")
    }
}

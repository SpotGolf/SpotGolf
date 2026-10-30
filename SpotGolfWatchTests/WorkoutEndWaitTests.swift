import XCTest
@testable import SpotGolfWatch

@MainActor
final class WorkoutEndWaitTests: XCTestCase {

    private var stops = 0
    private var wait: WorkoutEndWait!

    override func setUp() async throws {
        try await super.setUp()
        stops = 0
        wait = WorkoutEndWait(maxWait: 0.1) { [unowned self] in self.stops += 1 }
    }

    func testRoundWithNoStreamLeftStopsAtOnce() {
        wait.roundEnded(UUID(), hasStream: false)

        XCTAssertEqual(stops, 1)
        XCTAssertNil(wait.roundID)
    }

    func testWorkoutRunsUntilThePhoneHasTheStream() {
        let id = UUID()
        wait.roundEnded(id, hasStream: true)
        XCTAssertEqual(stops, 0)

        wait.streamComplete(id)

        XCTAssertEqual(stops, 1)
        XCTAssertNil(wait.roundID)
    }

    func testAnotherRoundsStreamDoesNotStop() {
        wait.roundEnded(UUID(), hasStream: true)

        wait.streamComplete(UUID())

        XCTAssertEqual(stops, 0)
    }

    func testStopsAfterTheLongestWait() async throws {
        wait.roundEnded(UUID(), hasStream: true)

        try await Task.sleep(for: .seconds(0.3))

        XCTAssertEqual(stops, 1)
    }

    func testStreamCompleteThenTimeoutStopsOnce() async throws {
        let id = UUID()
        wait.roundEnded(id, hasStream: true)
        wait.streamComplete(id)

        try await Task.sleep(for: .seconds(0.3))

        XCTAssertEqual(stops, 1)
    }

    func testNewRoundCancelsTheWait() async throws {
        let id = UUID()
        wait.roundEnded(id, hasStream: true)

        wait.cancel()
        wait.streamComplete(id)
        try await Task.sleep(for: .seconds(0.3))

        XCTAssertEqual(stops, 0)
    }
}

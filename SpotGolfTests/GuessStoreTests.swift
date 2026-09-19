import XCTest
import CoreLocation
@testable import SpotGolf

@MainActor
final class GuessStoreTests: XCTestCase {

    private var store: GuessStore!
    private let roundID = UUID()

    override func setUp() {
        super.setUp()
        store = GuessStore()
        store.deleteRound(roundID) // ensure clean state
    }

    private func makeGuess(holeIndex: Int = 0, reason: GuessReason = .stationary) -> MissedMarkGuess {
        MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07),
            holeIndex: holeIndex,
            reason: reason,
            roundID: roundID
        )
    }

    func testAddGuess() {
        let guess = makeGuess()
        store.add(guess)

        XCTAssertEqual(store.guesses(for: roundID, holeIndex: 0).count, 1)
        XCTAssertEqual(store.guesses(for: roundID, holeIndex: 0).first?.id, guess.id)
    }

    func testAddDuplicateIgnored() {
        let guess = makeGuess()
        store.add(guess)
        store.add(guess)

        XCTAssertEqual(store.guesses(for: roundID, holeIndex: 0).count, 1)
    }

    func testCapPerHole() {
        for _ in 0..<12 {
            store.add(makeGuess(holeIndex: 0))
        }

        XCTAssertEqual(store.guesses(for: roundID, holeIndex: 0).count, GuessStore.maxPerHole)
    }

    func testRemoveGuess() {
        let guess = makeGuess()
        store.add(guess)
        store.remove(guessID: guess.id, roundID: roundID)

        XCTAssertTrue(store.guesses(for: roundID, holeIndex: 0).isEmpty)
    }

    func testClearHole() {
        store.add(makeGuess(holeIndex: 0))
        store.add(makeGuess(holeIndex: 0))
        store.add(makeGuess(holeIndex: 1))

        store.clearHole(roundID: roundID, holeIndex: 0)

        XCTAssertTrue(store.guesses(for: roundID, holeIndex: 0).isEmpty)
        XCTAssertEqual(store.guesses(for: roundID, holeIndex: 1).count, 1)
    }

    func testDeleteRound() {
        store.add(makeGuess(holeIndex: 0))
        store.add(makeGuess(holeIndex: 1))

        store.deleteRound(roundID)

        XCTAssertTrue(store.guesses(for: roundID, holeIndex: 0).isEmpty)
        XCTAssertTrue(store.guesses(for: roundID, holeIndex: 1).isEmpty)
    }

    func testFilterByHoleIndex() {
        store.add(makeGuess(holeIndex: 0))
        store.add(makeGuess(holeIndex: 1))
        store.add(makeGuess(holeIndex: 1))

        XCTAssertEqual(store.guesses(for: roundID, holeIndex: 0).count, 1)
        XCTAssertEqual(store.guesses(for: roundID, holeIndex: 1).count, 2)
    }
}

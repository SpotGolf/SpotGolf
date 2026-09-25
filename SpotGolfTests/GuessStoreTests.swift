import XCTest
import CoreLocation
@testable import SpotGolf

@MainActor
final class GuessStoreTests: XCTestCase {

    private var directory: URL!
    private var store: GuessStore!
    private var round: Round!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = GuessStore(directory: directory)
        // Hole 1 from the start, hole 2 from 10 minutes in
        round = Round(date: Date(timeIntervalSince1970: 1_700_000_000), courseSelection: .test)
        round.startHole(1, at: round.date.addingTimeInterval(600), source: .autoAdvance)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        round = nil
        directory = nil
        super.tearDown()
    }

    /// A guess `seconds` after the round started.
    private func makeGuess(seconds: TimeInterval = 60) -> MissedMarkGuess {
        MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07),
            timestamp: round.date.addingTimeInterval(seconds),
            roundID: round.id
        )
    }

    func testAddGuess() {
        let guess = makeGuess()
        XCTAssertTrue(store.add(guess, in: round))

        XCTAssertEqual(store.guesses(for: round, holeIndex: 0).count, 1)
        XCTAssertEqual(store.guesses(for: round, holeIndex: 0).first?.id, guess.id)
    }

    func testAddDuplicateIgnored() {
        let guess = makeGuess()
        store.add(guess, in: round)

        XCTAssertFalse(store.add(guess, in: round))
        XCTAssertEqual(store.guesses(for: round.id).count, 1)
    }

    func testCapPerHole() {
        for i in 0..<12 {
            store.add(makeGuess(seconds: TimeInterval(i)), in: round)
        }

        XCTAssertEqual(store.guesses(for: round, holeIndex: 0).count, GuessStore.maxPerHole)
    }

    func testCapIsPerHoleOfTheTimeline() {
        for i in 0..<GuessStore.maxPerHole {
            store.add(makeGuess(seconds: TimeInterval(i)), in: round)
        }

        XCTAssertTrue(store.add(makeGuess(seconds: 700), in: round), "Hole 2 has its own cap")
    }

    func testRemoveGuess() {
        let guess = makeGuess()
        store.add(guess, in: round)
        store.remove(guessID: guess.id, roundID: round.id)

        XCTAssertTrue(store.guesses(for: round, holeIndex: 0).isEmpty)
    }

    func testRemovedGuessCannotComeBack() {
        let guess = makeGuess()
        store.add(guess, in: round)
        store.remove(guessID: guess.id, roundID: round.id)

        XCTAssertFalse(store.add(guess, in: round))
        XCTAssertFalse(GuessStore(directory: directory).add(guess, in: round), "Removed guesses are saved")
    }

    func testDeleteRound() {
        store.add(makeGuess(seconds: 60), in: round)
        store.add(makeGuess(seconds: 700), in: round)

        store.deleteRound(round.id)

        XCTAssertTrue(store.guesses(for: round.id).isEmpty)
    }

    func testFilterByTimelineHole() {
        store.add(makeGuess(seconds: 60), in: round)
        store.add(makeGuess(seconds: 700), in: round)
        store.add(makeGuess(seconds: 800), in: round)

        XCTAssertEqual(store.guesses(for: round, holeIndex: 0).count, 1)
        XCTAssertEqual(store.guesses(for: round, holeIndex: 1).count, 2)
    }

    func testCorrectedTimelineMovesGuesses() {
        store.add(makeGuess(seconds: 500), in: round)
        XCTAssertEqual(store.guesses(for: round, holeIndex: 0).count, 1)

        // Hole 2 really started at 5 minutes
        var entries = round.holeTimeline
        entries[1].startedAt = round.date.addingTimeInterval(300)
        round.holeTimeline = entries

        XCTAssertEqual(store.guesses(for: round, holeIndex: 1).count, 1)
    }

    func testGuessesSurviveNewStoreInstance() {
        let guess = makeGuess()
        store.add(guess, in: round)

        XCTAssertEqual(GuessStore(directory: directory).guesses(for: round.id), [guess])
    }
}

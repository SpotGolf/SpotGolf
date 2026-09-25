import XCTest
import CoreLocation
@testable import SpotGolf

final class MissedMarkGuessTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let guess = MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            roundID: UUID()
        )
        let data = try JSONEncoder().encode(guess)
        let decoded = try JSONDecoder().decode(MissedMarkGuess.self, from: data)

        XCTAssertEqual(decoded, guess)
    }

    func testCoordinateProperty() {
        let guess = MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07),
            roundID: UUID()
        )
        XCTAssertEqual(guess.coordinate.latitude, 33.45)
        XCTAssertEqual(guess.coordinate.longitude, -112.07)
    }

    // MARK: - Swing IDs

    func testSwingIDIsTheSameForTheSameSwing() {
        let roundID = UUID()
        let time = Date(timeIntervalSince1970: 1_700_000_000.123)

        XCTAssertEqual(MissedMarkGuess.id(forSwingAt: time, roundID: roundID),
                       MissedMarkGuess.id(forSwingAt: time, roundID: roundID))
    }

    func testSwingIDDiffersByTime() {
        let roundID = UUID()
        let time = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNotEqual(MissedMarkGuess.id(forSwingAt: time, roundID: roundID),
                          MissedMarkGuess.id(forSwingAt: time.addingTimeInterval(0.001), roundID: roundID))
    }

    func testSwingIDDiffersByRound() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNotEqual(MissedMarkGuess.id(forSwingAt: time, roundID: UUID()),
                          MissedMarkGuess.id(forSwingAt: time, roundID: UUID()))
    }
}

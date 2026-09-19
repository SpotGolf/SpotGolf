import XCTest
import CoreLocation
@testable import SpotGolf

final class MissedMarkGuessTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let guess = MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07),
            holeIndex: 2,
            reason: .swing,
            roundID: UUID()
        )
        let data = try JSONEncoder().encode(guess)
        let decoded = try JSONDecoder().decode(MissedMarkGuess.self, from: data)

        XCTAssertEqual(guess.id, decoded.id)
        XCTAssertEqual(guess.latitude, decoded.latitude)
        XCTAssertEqual(guess.longitude, decoded.longitude)
        XCTAssertEqual(guess.holeIndex, decoded.holeIndex)
        XCTAssertEqual(guess.reason, decoded.reason)
        XCTAssertEqual(guess.roundID, decoded.roundID)
    }

    func testCoordinateProperty() {
        let guess = MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07),
            holeIndex: 0,
            reason: .stationary,
            roundID: UUID()
        )
        XCTAssertEqual(guess.coordinate.latitude, 33.45)
        XCTAssertEqual(guess.coordinate.longitude, -112.07)
    }

    func testReasonCodable() throws {
        let swingData = try JSONEncoder().encode(GuessReason.swing)
        let decoded = try JSONDecoder().decode(GuessReason.self, from: swingData)
        XCTAssertEqual(decoded, .swing)

        let stationaryData = try JSONEncoder().encode(GuessReason.stationary)
        let decoded2 = try JSONDecoder().decode(GuessReason.self, from: stationaryData)
        XCTAssertEqual(decoded2, .stationary)
    }
}

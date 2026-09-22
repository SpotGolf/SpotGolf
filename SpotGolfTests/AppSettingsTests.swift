import XCTest
@testable import SpotGolf

final class AppSettingsTests: XCTestCase {

    func testDefaults() {
        let settings = AppSettings.default
        XCTAssertTrue(settings.missedMarkGuessesEnabled)
        XCTAssertEqual(settings.stationaryThreshold, 30)
    }

    func testCodableRoundTrip() throws {
        let settings = AppSettings(
            missedMarkGuessesEnabled: false,
            stationaryThreshold: 45
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings, decoded)
    }

    func testEquatable() {
        let a = AppSettings(missedMarkGuessesEnabled: true, stationaryThreshold: 30)
        let b = AppSettings(missedMarkGuessesEnabled: true, stationaryThreshold: 30)
        let c = AppSettings(missedMarkGuessesEnabled: false, stationaryThreshold: 30)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

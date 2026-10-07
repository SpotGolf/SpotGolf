import XCTest
@testable import SpotGolf

final class AppSettingsTests: XCTestCase {

    func testDefaults() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.stationaryThreshold, 30)
        XCTAssertTrue(settings.sharePins)
    }

    func testSettingsSavedBeforePinSharingTurnItOn() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"stationaryThreshold":45}"#.utf8))

        XCTAssertEqual(decoded, AppSettings(stationaryThreshold: 45, sharePins: true))
    }

    func testCodableRoundTrip() throws {
        let settings = AppSettings(stationaryThreshold: 45, sharePins: false)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings, decoded)
    }

    func testEquatable() {
        let a = AppSettings(stationaryThreshold: 30)
        let b = AppSettings(stationaryThreshold: 30)
        let c = AppSettings(stationaryThreshold: 45)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

import XCTest

/// The legend for the suggestion pins' colors: always along the bottom of the map, with the
/// Set Pin button above it on the green.
@MainActor
final class SuggestionLegendUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Near the Broadlands clubhouse, so Broadlands is in the course list, off hole 1's green.
    private static let start = (latitude: 39.95545, longitude: -105.04220)
    /// The middle of Broadlands hole 1's green.
    private static let holeOneGreen = (latitude: 39.954997, longitude: -105.045790)

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    private func dismissLocationAlert() {
        addUIInterruptionMonitor(withDescription: "Location Permission") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        app.tap()
    }

    func testTheLegendAlwaysShowsWithSetPinAboveIt() throws {
        LocationTestHelper.setSimulatorLocation(latitude: Self.start.latitude, longitude: Self.start.longitude)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        let legend = app.otherElements["SuggestionLegend"]
        let setPin = app.buttons["SetPinLocation"]
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "The legend should show on the map")
        XCTAssertEqual(legend.label, "Guess types: Green: Swing, Purple: Putt, Orange: 30s stop")
        XCTAssertFalse(setPin.exists, "Set Pin should show only on the green")

        LocationTestHelper.setSimulatorLocation(latitude: Self.holeOneGreen.latitude, longitude: Self.holeOneGreen.longitude)
        XCTAssertTrue(setPin.waitForExistence(timeout: 10), "Set Pin should show on the green")
        XCTAssertTrue(legend.exists, "The legend should stay on the green")
        XCTAssertLessThanOrEqual(setPin.frame.maxY, legend.frame.minY, "Set Pin should be above the legend")
    }
}

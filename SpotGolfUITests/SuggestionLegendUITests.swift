import XCTest

/// The legend for the suggestion pins' colors: along the bottom of the map while editing, and
/// gone when editing ends.
@MainActor
final class SuggestionLegendUITests: XCTestCase {

    private var app: XCUIApplication!

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

    func testTheLegendShowsOnlyWhileEditing() throws {
        // Broadlands only shows in the course list when the simulator is near it
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        let legend = app.otherElements["SuggestionLegend"]
        let editButton = app.buttons["EditHole"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "The map should have an Edit button")
        XCTAssertFalse(legend.exists, "The legend should wait for editing")

        editButton.tap()
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "Editing should show the legend")
        XCTAssertEqual(legend.label, "Guess types: Green: Swing, Purple: Putt, Orange: 30s stop")

        editButton.tap()
        XCTAssertTrue(legend.waitForNonExistence(timeout: 5), "Done should hide the legend")
    }
}

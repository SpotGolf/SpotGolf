import XCTest

/// The club picked for a spot in the Edit Spot sheet.
@MainActor
final class ClubSelectionUITests: XCTestCase {

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

    private var selectedClubs: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'Club-' AND selected == true"))
    }

    func testNewSpotHasAGuessedClubThatCanBeChangedAndKept() throws {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        // A first launch after an install takes longer to show the round list
        XCTAssertTrue(app.buttons["New Round"].waitForExistence(timeout: 20), "The round list should show")
        app.startRoundWithCourse()

        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5), "The edit sheet should open for the new spot")
        XCTAssertTrue(app.buttons["Club-pu"].waitForExistence(timeout: 5), "The bag's clubs should be listed")
        XCTAssertEqual(selectedClubs.count, 1, "One club should be guessed")

        let sevenIron = app.buttons["Club-7i"]
        sevenIron.tap()
        XCTAssertTrue(sevenIron.isSelected, "Tapping a club should select it")
        XCTAssertTrue(app.navigationBars["Edit Spot"].exists, "Picking a club should not close the sheet")
        app.buttons["Save"].tap()

        let spot = app.buttons["Stroke_1"]
        XCTAssertTrue(spot.waitForExistence(timeout: 5))
        spot.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Club-7i"].isSelected, "Save should keep the club")

        app.buttons["Club-pw"].tap()
        let penalty = app.buttons["StrokePenalty"]
        let outOfBounds = app.buttons["StrokeOutOfBounds"]
        penalty.tap()
        XCTAssertTrue(penalty.isSelected, "Tapping Penalty stroke should select it")
        XCTAssertTrue(app.navigationBars["Edit Spot"].exists, "Picking a type should not close the sheet")
        outOfBounds.tap()
        XCTAssertTrue(outOfBounds.isSelected && !penalty.isSelected, "Only one type can be selected")
        outOfBounds.tap()
        XCTAssertFalse(outOfBounds.isSelected, "Tapping the selected type clears it")
        penalty.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForNonExistence(timeout: 5))
        spot.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Club-pw"].isSelected, "A penalty stroke keeps the club picked with it")
        XCTAssertTrue(app.buttons["StrokePenalty"].isSelected, "Save should keep the type")
        app.buttons["Cancel"].tap()
    }

}

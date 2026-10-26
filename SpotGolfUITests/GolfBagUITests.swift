import XCTest

/// The golf bag in Settings: the clubs carried, at most 14.
@MainActor
final class GolfBagUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testBagStartsStandardAndHoldsFourteen() throws {
        app.launch()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "The round list should have a Settings button")
        settings.tap()
        let openBag = app.buttons["OpenGolfBag"]
        XCTAssertTrue(openBag.waitForExistence(timeout: 5), "Settings should have a Golf Bag link")
        XCTAssertTrue(openBag.label.contains("14 clubs"), "Settings should show the club count, not '\(openBag.label)'")
        openBag.tap()
        XCTAssertTrue(app.navigationBars["Golf Bag"].waitForExistence(timeout: 5), "The bag should open")

        let count = app.staticTexts["BagCount"]
        XCTAssertEqual(count.label, "14 of 14 clubs")
        let driver = app.buttons["Club-dr"]
        let fiveWood = app.buttons["Club-5w"]
        let twoWood = app.buttons["Club-2w"]
        XCTAssertTrue(driver.isSelected, "The driver is in the standard bag")
        XCTAssertFalse(twoWood.isSelected, "The 2 wood is not in the standard bag")
        XCTAssertFalse(twoWood.isEnabled, "A full bag takes no more clubs")

        fiveWood.tap()
        XCTAssertFalse(fiveWood.isSelected, "Tapping a club in the bag takes it out")
        XCTAssertEqual(count.label, "13 of 14 clubs")
        XCTAssertTrue(twoWood.isEnabled, "A bag with room takes a club")

        twoWood.tap()
        XCTAssertTrue(twoWood.isSelected, "Tapping a club out of the bag adds it")
        XCTAssertEqual(count.label, "14 of 14 clubs")

        app.navigationBars["Golf Bag"].buttons.firstMatch.tap()
        XCTAssertTrue(openBag.waitForExistence(timeout: 5), "Settings should show again")
        XCTAssertTrue(openBag.label.contains("14 clubs"), "Settings should show the new count, not '\(openBag.label)'")
    }

    func testEditDistance() throws {
        app.launch()

        app.buttons["Settings"].tap()
        let openBag = app.buttons["OpenGolfBag"]
        XCTAssertTrue(openBag.waitForExistence(timeout: 5), "Settings should have a Golf Bag link")
        openBag.tap()
        let editDistances = app.buttons["EditDistances"]
        XCTAssertTrue(editDistances.waitForExistence(timeout: 5), "The bag should have a Distances button")
        editDistances.tap()
        XCTAssertTrue(app.navigationBars["Club Distances"].waitForExistence(timeout: 5), "The distances should open")

        let driver = app.textFields["Distance-dr"]
        XCTAssertEqual(driver.value as? String, "230", "The driver starts at its default")
        XCTAssertFalse(app.textFields["Distance-pu"].exists, "The putter has no distance")

        // The field empties on focus, so typing replaces the distance
        driver.tap()
        driver.typeText("245")
        XCTAssertEqual(driver.value as? String, "245")
        app.navigationBars["Club Distances"].buttons["Done"].tap()

        app.navigationBars["Club Distances"].buttons.firstMatch.tap()
        XCTAssertTrue(editDistances.waitForExistence(timeout: 5), "The bag should show again")
        editDistances.tap()
        XCTAssertEqual(app.textFields["Distance-dr"].value as? String, "245", "The new distance should be saved")
    }

}

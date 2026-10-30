import XCTest

/// Green View: the close-up of the green, opened from its button.
extension InRoundUITests {
    /// The middle of Broadlands hole 1's green.
    static let holeOneGreen = (latitude: 39.954997, longitude: -105.045790)

    private var greenViewButton: XCUIElement { app.buttons["GreenView"] }
    private var closeGreenViewButton: XCUIElement { app.buttons["CloseGreenView"] }
    private var greenViewTitle: XCUIElement { element("GreenViewTitle") }

    func testButtonOpensGreenViewAndXClosesIt() throws {
        app.goToHole(1)
        XCTAssertTrue(greenViewButton.waitToExist(), "The Green View button should be with the map buttons")
        XCTAssertFalse(greenViewTitle.exists, "Green View should not show before it is opened")

        greenViewButton.tap()
        XCTAssertTrue(greenViewTitle.waitToExist(), "The button should open Green View")
        XCTAssertTrue(closeGreenViewButton.exists, "Green View should have an X")
        XCTAssertFalse(app.buttons["MapStyle"].exists, "The map's buttons should be hidden in Green View")
        XCTAssertTrue(element("GreenViewPinDistance").exists, "The feet to the pin should show during a round")
        XCTAssertFalse(greenViewButton.exists, "The Green View button should be hidden in Green View")
        XCTAssertTrue(app.buttons["TapIn"].exists, "Green View should have the Tap in button")

        // A tap on the ground drops no target, as it would on the map
        element("GreenViewGround").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertFalse(element("Target").exists, "A tap in Green View should not drop a target")

        closeGreenViewButton.tap()
        XCTAssertTrue(greenViewTitle.waitToVanish(), "X should close Green View")
        XCTAssertTrue(greenViewButton.waitToExist(), "The map's buttons should come back")
        XCTAssertTrue(app.maps.firstMatch.exists, "The map should show again")
        XCTAssertFalse(app.buttons["TapIn"].exists, "Tap in should be in Green View only")
    }

    func testSpotAddedInGreenViewShowsOnTheMap() throws {
        _ = freshHole()
        greenViewButton.tap()
        let ground = element("GreenViewGround")
        XCTAssertTrue(ground.waitToExist(), "Green View should open")
        // Left of center, clear of the flag Green View centers on
        ground.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55)).press(forDuration: 0.6)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "A long press should add a spot and open it")
        saveInSheet()
        XCTAssertTrue(app.buttons["Stroke_1"].waitToExist(), "The spot should show in Green View")

        closeGreenViewButton.tap()
        XCTAssertTrue(greenViewTitle.waitToVanish())
        // The spot sits at the far end of the hole on the map, so the hole's count shows it was saved
        let strokes = app.staticTexts["HoleStrokes"]
        XCTAssertTrue(strokes.waitToExist())
        XCTAssertTrue(strokes.label.contains("1 stroke"), "The hole should count the spot: \(strokes.label)")
    }

    func testTapInAddsAPuttWithoutOpeningIt() throws {
        _ = freshHole()
        greenViewButton.tap()
        let ground = element("GreenViewGround")
        XCTAssertTrue(ground.waitToExist(), "Green View should open")
        ground.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55)).press(forDuration: 0.6)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "A long press should add a spot and open it")
        saveInSheet()
        XCTAssertTrue(app.buttons["Stroke_1"].waitToExist(), "The spot should show in Green View")

        app.buttons["TapIn"].tap()
        let putt = app.buttons["Stroke_2"].firstMatch
        XCTAssertTrue(putt.waitToExist(), "Tap in should add the hole's next stroke")
        XCTAssertTrue(putt.label.contains("Putter"), "A tap in is a putt: \(putt.label)")
        XCTAssertFalse(app.navigationBars["Edit Spot"].exists, "Tap in should not open the spot sheet")
    }

    func testGreenViewStaysClosedWhenThePlayerWalksOntoTheGreen() throws {
        app.goToHole(1)
        XCTAssertFalse(greenViewTitle.exists, "Green View should not show off the green")

        // Set Pin shows once the app has the player on the green
        moveTo(latitude: Self.holeOneGreen.latitude, longitude: Self.holeOneGreen.longitude)
        XCTAssertTrue(app.buttons["SetPinLocation"].waitToExist(), "The app should see the player on the green")
        XCTAssertFalse(greenViewTitle.exists, "Only the Green View button should open Green View")
    }
}

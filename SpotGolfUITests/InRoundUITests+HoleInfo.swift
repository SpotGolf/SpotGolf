import XCTest

/// The hole shown, and what the header and key information boxes say about it.
extension InRoundUITests {
    /// Broadlands hole 2's tee box.
    private static let holeTwoTee = (latitude: 39.95501, longitude: -105.04718)

    private var summary: XCUIElement { app.staticTexts["HoleSummary"] }
    private var distanceToCenter: XCUIElement { element("DistanceToCenter") }

    func testHeaderAndKeyInformationShowCourseData() throws {
        app.goToHole(1)

        // Under the hole circles: par, then the tee picked
        XCTAssertTrue(summary.waitToExist(), "Par and tee should appear under the hole circles")
        XCTAssertEqual(summary.label, "Par 4 - Gold")

        // Key information boxes on the right of the map, once the location is in
        XCTAssertTrue(UIWait.until { distanceToCenter.exists && distanceToCenter.label.first?.isNumber == true },
                      "Distance box should show yards, not '\(distanceToCenter.label)'")
        XCTAssertTrue(element("ElevationChange").exists, "Elevation change box should exist")
    }

    func testSelectingHoleShowsItWithNothingToConfirm() throws {
        app.goToHole(1)

        // Any hole can be shown, forward or back, with nothing to confirm or go back to
        app.goToHole(3)
        XCTAssertFalse(app.buttons["Resume round"].exists, "There is no round position to go back to")
        XCTAssertFalse(app.buttons["Play hole"].exists, "Showing a hole is all there is to do")

        app.goToHole(1)
    }

    func testPhoneLocationDoesNotChangeHole() throws {
        app.goToHole(1)
        XCTAssertTrue(UIWait.until { distanceToCenter.exists && distanceToCenter.label.first?.isNumber == true },
                      "Distance box should show yards")
        let before = distanceToCenter.label

        // Only the watch's GPS changes the hole. The distance changing shows the app has the new location.
        moveTo(latitude: Self.holeTwoTee.latitude, longitude: Self.holeTwoTee.longitude)
        XCTAssertTrue(UIWait.until { distanceToCenter.label != before }, "The distance should follow the location")

        XCTAssertTrue(app.waitForShownHole(1), "Hole 1 should stay shown")
    }

    func testHeaderAndHazardsUpdateOnHoleChange() throws {
        app.goToHole(1)
        XCTAssertTrue(summary.waitToExist(), "Par and tee should appear for hole 1")
        XCTAssertEqual(summary.label, "Par 4 - Gold")

        // Show hole 2, then move the location to its tee so distances update
        app.goToHole(2)
        moveTo(latitude: Self.holeTwoTee.latitude, longitude: Self.holeTwoTee.longitude)

        // Hole 2 is also par 4 from the Gold tee
        XCTAssertEqual(summary.label, "Par 4 - Gold")

        // Hole 2 has bunkers between the tee and the green: each gets a yardage bubble on the map
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Hazard in '")).firstMatch
        XCTAssertTrue(bubble.waitToExist(), "Hazard bubbles should appear for hole 2")
    }
}

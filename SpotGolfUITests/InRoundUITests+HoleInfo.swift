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

    func testDotMenuChangesTheTee() throws {
        app.goToHole(1)
        XCTAssertTrue(summary.waitToExist(), "Par and tee should appear under the hole circles")
        XCTAssertEqual(summary.label, "Par 4 - Gold")

        pickTee("Blue")
        XCTAssertTrue(UIWait.until { summary.label == "Par 4 - Blue" }, "The header should show the new tee, not '\(summary.label)'")

        // Back to the tee the other tests read
        pickTee("Gold")
        XCTAssertTrue(UIWait.until { summary.label == "Par 4 - Gold" }, "The header should show the tee again, not '\(summary.label)'")
    }

    /// Opens the dot menu's Tee item and picks `tee`.
    private func pickTee(_ tee: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu = app.buttons["MapMenu"]
        XCTAssertTrue(menu.waitToExist(), "The dot menu should be on the map", file: file, line: line)
        menu.tap()
        let teeItem = app.buttons["Tee"]
        XCTAssertTrue(teeItem.waitToExist(), "The dot menu should have Tee", file: file, line: line)
        teeItem.tap()
        // A menu picker's items keep no identifier of their own, so by name
        let item = app.buttons[tee]
        XCTAssertTrue(item.waitToExist(), "The \(tee) tee should be listed", file: file, line: line)
        item.tap()
        XCTAssertTrue(item.waitToVanish(), "Picking a tee should close the dot menu", file: file, line: line)
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

    func testSpotOnAHazardBubbleCanBeAddedAndOpened() throws {
        app.goToHole(2)
        moveTo(latitude: Self.holeTwoTee.latitude, longitude: Self.holeTwoTee.longitude)
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Hazard in '")).firstMatch
        XCTAssertTrue(bubble.waitToExist(), "Hazard bubbles should appear for hole 2")
        let before = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'Stroke_'")).count

        // A long press on a bubble goes through it to the map and adds a spot, whose pin stands
        // over the bubble
        let frame = bubble.frame
        let onBubble = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.maxY))
        onBubble.press(forDuration: 1.0)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "A long press on a bubble should add a spot")
        saveInSheet()

        // The bubble does not cover the pin, and its cut-out copy of the pin is not a second spot
        let spots = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'Stroke_'"))
        XCTAssertTrue(UIWait.until { spots.count == before + 1 }, "One spot should be added, not \(spots.count - before)")
        XCTAssertTrue(bubble.exists, "The bubble should still be there")
    }
}

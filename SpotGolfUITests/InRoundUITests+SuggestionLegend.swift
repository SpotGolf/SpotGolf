import XCTest

/// The legend of suggestion pin colors on the map.
extension InRoundUITests {
    func testTheLegendAlwaysShowsWithSetPinAboveIt() throws {
        app.goToHole(1)
        let legend = app.otherElements["SuggestionLegend"]
        let setPin = app.buttons["SetPinLocation"]
        XCTAssertTrue(legend.waitToExist(), "The legend should show on the map")
        XCTAssertEqual(legend.label, "Guess types: Green: Swing, Purple: Putt, Orange: 30s stop")
        XCTAssertFalse(setPin.exists, "Set Pin should show only on the green")

        moveTo(latitude: Self.holeOneGreen.latitude, longitude: Self.holeOneGreen.longitude)
        XCTAssertTrue(setPin.waitToExist(), "Set Pin should show on the green")
        XCTAssertTrue(legend.exists, "The legend should stay on the green")
        XCTAssertLessThanOrEqual(setPin.frame.maxY, legend.frame.minY, "Set Pin should be above the legend")
    }
}

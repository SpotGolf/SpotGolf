import XCTest

/// The OpenStreetMap credit the course data's license requires wherever the data is shown.
extension InRoundUITests {
    func testTheCreditShowsOnTheMapAndOverTheGreenView() throws {
        let credit = element("MapCredit")
        XCTAssertTrue(credit.waitToExist(), "The map should show the OpenStreetMap credit")

        tapMapMenuItem("GreenView")
        let close = app.buttons["CloseGreenView"]
        XCTAssertTrue(close.waitToExist(), "Green View should open")
        XCTAssertTrue(credit.isHittable, "The credit should show over Green View")
        close.tap()
        XCTAssertTrue(close.waitToVanish(), "Green View should close")
    }
}

import XCTest

/// Green View: the hole's green drawn by the app, for putts. See plans/2026-10-17-green-view.md.
@MainActor
final class GreenViewUITests: XCTestCase {

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

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var greenViewButton: XCUIElement { app.buttons["GreenView"] }
    private var closeButton: XCUIElement { app.buttons["CloseGreenView"] }
    private var title: XCUIElement { element("GreenViewTitle") }

    private func startRound() {
        LocationTestHelper.setSimulatorLocation(latitude: Self.start.latitude, longitude: Self.start.longitude)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()
    }

    func testButtonOpensGreenViewAndXClosesIt() throws {
        startRound()

        XCTAssertTrue(greenViewButton.waitForExistence(timeout: 5), "The Green View button should be with the map buttons")
        XCTAssertFalse(title.exists, "Green View should not show before it is opened")
        greenViewButton.tap()

        XCTAssertTrue(title.waitForExistence(timeout: 5), "The button should open Green View")
        XCTAssertTrue(closeButton.exists, "Green View should have an X")
        XCTAssertFalse(app.buttons["MapStyle"].exists, "The map's buttons should be hidden in Green View")
        XCTAssertTrue(element("GreenViewPinDistance").exists, "The feet to the pin should show during a round")
        XCTAssertTrue(app.buttons["Hole times"].exists, "Green View should be in edit mode")
        XCTAssertFalse(app.buttons["EditHole"].exists, "Green View is always in edit mode, so it has no Edit button")
        XCTAssertFalse(greenViewButton.exists, "The Green View button should be hidden in Green View")

        // A tap on the ground drops no target, as it would on the map
        element("GreenViewGround").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(1)
        XCTAssertFalse(element("Target").exists, "A tap in Green View should not drop a target")

        closeButton.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "X should close Green View")
        XCTAssertTrue(app.buttons["EditHole"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["EditHole"].label, "Edit", "X should end editing")
        XCTAssertTrue(greenViewButton.waitForExistence(timeout: 5), "The map's buttons should come back")
        XCTAssertTrue(app.maps.firstMatch.exists, "The map should show again")
    }

    func testSpotAddedInGreenViewShowsOnTheMap() throws {
        startRound()
        XCTAssertTrue(greenViewButton.waitForExistence(timeout: 5))
        greenViewButton.tap()
        let ground = element("GreenViewGround")
        XCTAssertTrue(ground.waitForExistence(timeout: 5), "Green View should open while editing")

        let press = ground.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        press.press(forDuration: 1.0)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5),
                      "A long press while editing should add a spot and open it")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stroke_1"].waitForExistence(timeout: 5), "The spot should show in Green View")

        closeButton.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        // The spot sits at the far end of the hole on the map, so the hole's count shows it was saved
        let summary = app.staticTexts["HoleStrokes"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 stroke"), "The hole should count the spot: \(summary.label)")
    }

    func testOpensWhenThePlayerWalksOntoTheGreen() throws {
        startRound()
        XCTAssertFalse(title.exists, "Green View should not show off the green")

        LocationTestHelper.setSimulatorLocation(latitude: Self.holeOneGreen.latitude, longitude: Self.holeOneGreen.longitude)
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Walking onto the green should open Green View")

        // Closed with X, it stays closed on this hole
        closeButton.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        LocationTestHelper.setSimulatorLocation(latitude: Self.start.latitude, longitude: Self.start.longitude)
        sleep(2)
        LocationTestHelper.setSimulatorLocation(latitude: Self.holeOneGreen.latitude, longitude: Self.holeOneGreen.longitude)
        sleep(3)
        XCTAssertFalse(title.exists, "Green View closed with X should not open again on the same hole")
    }
}

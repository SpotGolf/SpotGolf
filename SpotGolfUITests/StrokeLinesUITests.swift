import XCTest

/// The ruler button in the map's left capsule shows and hides the lines between the hole's
/// strokes, with the yards along each.
@MainActor
final class StrokeLinesUITests: XCTestCase {

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

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Adds a spot in Green View at `point` on its ground and saves it.
    private func addSpotInGreenView(at point: CGVector) {
        element("GreenViewGround").coordinate(withNormalizedOffset: point).press(forDuration: 1.0)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5), "A long press should add a spot")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForNonExistence(timeout: 5))
    }

    func testRulerShowsAndHidesTheLinesBetweenStrokes() throws {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        // Three strokes on hole 1, so two lines
        let greenView = app.buttons["GreenView"]
        XCTAssertTrue(greenView.waitForExistence(timeout: 5))
        greenView.tap()
        XCTAssertTrue(element("GreenViewGround").waitForExistence(timeout: 5))
        for y in [0.35, 0.5, 0.65] {
            addSpotInGreenView(at: CGVector(dx: 0.5, dy: y))
        }
        app.buttons["CloseGreenView"].tap()

        let ruler = app.buttons["StrokeLines"]
        let firstDistance = element("StrokeDistance_1")
        XCTAssertTrue(ruler.waitForExistence(timeout: 5), "The ruler should be in the left capsule")
        XCTAssertFalse(firstDistance.exists, "No distances before the ruler is tapped")

        ruler.tap()
        XCTAssertTrue(firstDistance.waitForExistence(timeout: 5), "The ruler should show the yards between strokes")
        XCTAssertTrue(element("StrokeDistance_2").exists, "There should be a line from stroke 2 to stroke 3")
        XCTAssertFalse(element("StrokeDistance_3").exists, "There should be no line past the last stroke")
        XCTAssertNotNil(Int(firstDistance.label.split(separator: " ").first ?? ""), "The label should be yards")

        ruler.tap()
        XCTAssertTrue(firstDistance.waitForNonExistence(timeout: 5), "Tapping the ruler again should hide the lines")
    }
}

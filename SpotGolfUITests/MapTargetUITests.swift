import XCTest

final class MapTargetUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
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

    private var target: XCUIElement {
        app.descendants(matching: .any)["Target"]
    }

    private var clearButton: XCUIElement {
        app.buttons["ClearTarget"]
    }

    /// Taps the map a little above its center, away from the player's own location.
    private func tapMap() {
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5), "The map should show")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    }

    func testTapShowsTargetWithYardsAndClearRemovesIt() throws {
        // Broadlands only shows in the course list when the simulator is near it
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        XCTAssertFalse(target.exists, "No target before a tap")
        XCTAssertFalse(clearButton.exists, "No clear button before a tap")

        tapMap()

        XCTAssertTrue(target.waitForExistence(timeout: 5), "A tap should show the target")
        XCTAssertTrue(target.label.hasPrefix("Target, "), "The target should show its yards: \(target.label)")
        XCTAssertTrue(target.label.hasSuffix(" yards"), "The target should show its yards: \(target.label)")
        XCTAssertTrue(clearButton.exists, "The clear button should show with a target")

        clearButton.tap()

        XCTAssertTrue(target.waitForNonExistence(timeout: 5), "Clear should remove the target")
        XCTAssertFalse(clearButton.exists, "The clear button should go away with the target")
    }

    func testTapWhileEditingDoesNotShowTarget() throws {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        app.buttons["EditHole"].tap()
        tapMap()

        // Give a target time to show, if it wrongly would
        XCTAssertFalse(target.waitForExistence(timeout: 2), "Taps while editing are for spots, not targets")
        XCTAssertFalse(clearButton.exists)
    }
}

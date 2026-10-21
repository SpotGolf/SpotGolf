import XCTest

@MainActor
final class MapTargetUITests: XCTestCase {

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

    private var target: XCUIElement {
        app.descendants(matching: .any)["Target"]
    }

    private var clearButton: XCUIElement {
        app.buttons["ClearTarget"]
    }

    /// The yards from the player to the target, in the box on the left.
    private var distanceToTarget: XCUIElement {
        app.descendants(matching: .any)["DistanceToTarget"]
    }

    /// The yards from the target to the center of the green, in the box under it.
    private var targetToGreen: XCUIElement {
        app.descendants(matching: .any)["TargetToGreen"]
    }

    private func assertShowsYards(_ box: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(box.exists, "\(name) should show with a target", file: file, line: line)
        XCTAssertNotNil(box.label.range(of: #"^\d+"#, options: .regularExpression),
                        "\(name) should show its yards: \(box.label)", file: file, line: line)
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
        XCTAssertFalse(distanceToTarget.exists, "No distance boxes before a tap")
        XCTAssertFalse(clearButton.exists, "No clear button before a tap")

        tapMap()

        XCTAssertTrue(target.waitForExistence(timeout: 5), "A tap should show the target")
        assertShowsYards(distanceToTarget, "The yards to the point")
        assertShowsYards(targetToGreen, "The yards from the point to the green")
        XCTAssertTrue(clearButton.exists, "The clear button should show with a target")

        clearButton.tap()

        XCTAssertTrue(target.waitForNonExistence(timeout: 5), "Clear should remove the target")
        XCTAssertFalse(distanceToTarget.exists, "The distance boxes should go away with the target")
        XCTAssertFalse(targetToGreen.exists, "The distance boxes should go away with the target")
        XCTAssertFalse(clearButton.exists, "The clear button should go away with the target")
    }

    func testTapOnASpotOpensItAndShowsNoTarget() throws {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "A long press should add a spot and open it")
        save.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForNonExistence(timeout: 5))

        let stroke = app.buttons["Stroke_1"]
        XCTAssertTrue(stroke.waitForExistence(timeout: 5))
        stroke.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5), "A tap on a spot should open it")
        XCTAssertFalse(target.exists, "A tap on a spot should not drop a target")
        app.buttons["Cancel"].tap()
    }
}

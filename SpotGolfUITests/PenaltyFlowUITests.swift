import XCTest

@MainActor
final class PenaltyFlowUITests: XCTestCase {

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

    /// Sets the simulator location to the Hole 1 tee box area at Broadlands.
    private func setLocationToHole1Tee() {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
    }

    // MARK: - Penalty Flow Test

    func testPenaltyAndOutOfBoundsStrokeing() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        let locations = LocationTestHelper.loadTestLocations(from: "test-locations-penalties")
        XCTAssertEqual(locations.count, 14, "Penalty test CSV should have 14 locations")

        // Start round with Broadlands course
        app.startRoundWithCourse()

        var currentHole = 1
        var strokesOnHole = 0

        // Stroke each location, applying penalty/OB types as specified
        for (index, location) in locations.enumerated() {
            let targetHole = location.hole

            // Navigate to the correct hole
            if currentHole != targetHole {
                app.goToHole(targetHole)
                currentHole = targetHole
                strokesOnHole = 0
                sleep(1)
            }

            // Strokes are placed by hand, so the spot comes from the press and not from GPS
            app.addStroke(at: XCUIApplication.strokePressPoints[strokesOnHole])
            strokesOnHole += 1
            XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5),
                          "Edit sheet should open for the new stroke at location \(index)")

            // The edit sheet closes itself once a type is picked
            switch location.type {
            case .outOfBounds:
                let obButton = app.buttons["Out of bounds"]
                XCTAssertTrue(obButton.waitForExistence(timeout: 5),
                              "Out of bounds button should exist in edit sheet")
                obButton.tap()
            case .penalty:
                let penaltyButton = app.buttons["Penalty stroke"]
                XCTAssertTrue(penaltyButton.waitForExistence(timeout: 5),
                              "Penalty stroke button should exist in edit sheet")
                penaltyButton.tap()
            default:
                app.buttons["Save"].tap()
            }
            sleep(1)
        }

        // Hole 1: 8 strokes (tee, OB, re-tee, 5 more)
        app.goToHole(1)
        XCTAssertTrue(app.buttons["Stroke_8"].waitForExistence(timeout: 5), "Hole 1 should have 8 strokes")
        XCTAssertFalse(app.buttons["Stroke_9"].exists, "Hole 1 should have no more than 8 strokes")

        // Hole 2: 6 strokes (tee, 2nd shot, penalty, drop, shot, putt)
        app.goToHole(2)
        XCTAssertTrue(app.buttons["Stroke_6"].waitForExistence(timeout: 5), "Hole 2 should have 6 strokes")
        XCTAssertFalse(app.buttons["Stroke_7"].exists, "Hole 2 should have no more than 6 strokes")
    }
}

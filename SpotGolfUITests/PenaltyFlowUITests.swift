import XCTest

final class PenaltyFlowUITests: XCTestCase {

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

    /// Sets the simulator location to the Hole 1 tee box area at Broadlands.
    private func setLocationToHole1Tee() {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
    }

    // MARK: - Penalty Flow Test

    func testPenaltyAndOutOfBoundsMarking() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        let locations = LocationTestHelper.loadTestLocations(from: "test-locations-penalties")
        XCTAssertEqual(locations.count, 14, "Penalty test CSV should have 14 locations")

        // Start round with Broadlands course
        startRoundWithCourse()

        var currentHole = 1
        var marksOnHole = 0

        // Mark each location, applying penalty/OB types as specified
        for (index, location) in locations.enumerated() {
            let targetHole = location.hole

            // Navigate to the correct hole
            if currentHole != targetHole {
                app.goToHole(targetHole)
                currentHole = targetHole
                marksOnHole = 0
                sleep(1)
            }

            // Marks are placed by hand, so the spot comes from the press and not from GPS
            addMark(at: Self.pressPoints[marksOnHole])
            marksOnHole += 1
            XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5),
                          "Edit sheet should open for the new mark at location \(index)")

            // The edit sheet closes itself once a type is picked
            switch location.type {
            case .outOfBounds:
                let obButton = app.buttons["Mark out of bounds"]
                XCTAssertTrue(obButton.waitForExistence(timeout: 5),
                              "Mark out of bounds button should exist in edit sheet")
                obButton.tap()
            case .penalty:
                let penaltyButton = app.buttons["Mark as penalty"]
                XCTAssertTrue(penaltyButton.waitForExistence(timeout: 5),
                              "Mark as penalty button should exist in edit sheet")
                penaltyButton.tap()
            default:
                app.buttons["Save"].tap()
            }
            sleep(1)
        }

        // Hole 1: 8 marks (tee, OB, re-tee, 5 more)
        app.goToHole(1)
        XCTAssertTrue(app.buttons["SpotMark_8"].waitForExistence(timeout: 5), "Hole 1 should have 8 marks")
        XCTAssertFalse(app.buttons["SpotMark_9"].exists, "Hole 1 should have no more than 8 marks")

        // Hole 2: 6 marks (tee, 2nd shot, penalty, drop, shot, putt)
        app.goToHole(2)
        XCTAssertTrue(app.buttons["SpotMark_6"].waitForExistence(timeout: 5), "Hole 2 should have 6 marks")
        XCTAssertFalse(app.buttons["SpotMark_7"].exists, "Hole 2 should have no more than 6 marks")
    }

    // MARK: - Helpers

    /// Spots on the map, as fractions of the screen. They stay clear of the header, the key
    /// information boxes and the buttons, and far enough apart that a press never lands on an
    /// earlier mark.
    private static let pressPoints: [CGVector] = [0.42, 0.52, 0.62].flatMap { y in
        [0.2, 0.4, 0.6, 0.8].map { x in CGVector(dx: x, dy: y) }
    }

    /// Long-presses the map, which adds a mark there and opens its edit sheet.
    private func addMark(at point: CGVector) {
        let start = app.coordinate(withNormalizedOffset: point)
        // The map only reports the press once the finger has moved
        start.press(forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 4)))
    }

    private func startRoundWithCourse() {
        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5))
        newRoundButton.tap()

        let broadlands = app.staticTexts["Broadlands Golf Course"]
        XCTAssertTrue(broadlands.waitForExistence(timeout: 10))
        broadlands.tap()

        let startButton = app.buttons["Start Round"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.waitForCurrentHole(1))
    }
}

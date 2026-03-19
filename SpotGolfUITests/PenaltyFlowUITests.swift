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

        // Mark each location, applying penalty/OB types as specified
        for (index, location) in locations.enumerated() {
            let targetHole = location.hole

            // Navigate to the correct hole
            while currentHole < targetHole {
                let nextButton = app.buttons["Next"]
                XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Next button should exist")
                nextButton.tap()
                currentHole += 1
                sleep(1)

                let holeLabel = app.staticTexts["Hole \(currentHole)"]
                XCTAssertTrue(holeLabel.waitForExistence(timeout: 5),
                              "Hole \(currentHole) label should appear")
            }

            // Set GPS location and mark ball
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                     longitude: location.longitude)
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 5), "At my ball button should exist")
            atMyBall.tap()
            sleep(2)

            // If this mark needs a type, re-center map and tap the mark
            if location.type == .outOfBounds || location.type == .penalty {
                // Re-center map on current location so the mark is visible
                let locationButton = app.buttons.matching(NSPredicate(
                    format: "identifier == 'location' OR identifier == 'location.fill'")).firstMatch
                locationButton.tap()
                sleep(2)

                let marksOnThisHole = locations[0...index].filter { $0.hole == targetHole }.count
                let spotButton = app.buttons["SpotMark_\(marksOnThisHole)"]
                XCTAssertTrue(spotButton.waitForExistence(timeout: 10),
                              "SpotMark_\(marksOnThisHole) button should exist for location \(index)")
                spotButton.tap()
                sleep(1)

                if location.type == .outOfBounds {
                    let obButton = app.buttons["Mark out of bounds"]
                    XCTAssertTrue(obButton.waitForExistence(timeout: 5),
                                  "Mark out of bounds button should exist in edit sheet")
                    obButton.tap()
                } else {
                    let penaltyButton = app.buttons["Mark as penalty"]
                    XCTAssertTrue(penaltyButton.waitForExistence(timeout: 5),
                                  "Mark as penalty button should exist in edit sheet")
                    penaltyButton.tap()
                }
                sleep(1)
            }
        }

        // Navigate back to hole 1 to verify stroke counts
        while currentHole > 1 {
            let prevButton = app.buttons["Prev"]
            XCTAssertTrue(prevButton.waitForExistence(timeout: 5))
            prevButton.tap()
            currentHole -= 1
            sleep(1)
        }

        // Hole 1: 8 marks (tee, OB, re-tee, 5 more) = 7 strokes
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5))
        let strokes7 = app.staticTexts["7"]
        XCTAssertTrue(strokes7.waitForExistence(timeout: 5),
                      "Hole 1 should show 7 strokes (OB from tee, re-tee)")

        // Navigate to hole 2
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        sleep(1)

        // Hole 2: 6 marks (tee, 2nd shot, penalty, drop, shot, putt) = 5 strokes
        let hole2Label = app.staticTexts["Hole 2"]
        XCTAssertTrue(hole2Label.waitForExistence(timeout: 5))
        let strokes5 = app.staticTexts["5"]
        XCTAssertTrue(strokes5.waitForExistence(timeout: 5),
                      "Hole 2 should show 5 strokes (penalty from water)")
    }

    // MARK: - Helpers

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

        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5))
    }
}

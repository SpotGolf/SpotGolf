import XCTest

/// The map button on the round map: it opens the style sheet, a pick applies and closes it,
/// and the map opens with the last style picked.
@MainActor
final class MapStyleUITests: XCTestCase {

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

    private var mapStyleButton: XCUIElement {
        app.buttons["MapStyle"]
    }

    private func assertMapStyle(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let value = mapStyleButton.value as? String ?? ""
        XCTAssertEqual(value, title, "The map button should say \(title), not '\(value)'", file: file, line: line)
    }

    /// Opens the sheet from the map button and picks a style by its identifier suffix.
    private func pickMapStyle(_ choice: String, file: StaticString = #filePath, line: UInt = #line) {
        mapStyleButton.tap()
        let option = app.buttons["MapStyle-\(choice)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The sheet should offer \(choice)", file: file, line: line)
        option.tap()
        XCTAssertTrue(option.waitForNonExistence(timeout: 5), "A pick should close the sheet", file: file, line: line)
    }

    func testTheMapButtonOpensTheSheetAndTheMapOpensWithTheLastPick() throws {
        // Broadlands only shows in the course list when the simulator is near it
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        XCTAssertTrue(mapStyleButton.waitForExistence(timeout: 5), "The map should have a map style button")
        assertMapStyle("Standard")

        mapStyleButton.tap()
        let standard = app.buttons["MapStyle-standard"]
        XCTAssertTrue(standard.waitForExistence(timeout: 5), "The sheet should list the styles")
        XCTAssertTrue(standard.isSelected, "The sheet should mark the current style")
        app.buttons["CloseMapStyles"].tap()
        XCTAssertTrue(standard.waitForNonExistence(timeout: 5), "Close should close the sheet")
        assertMapStyle("Standard")

        pickMapStyle("hybrid")
        assertMapStyle("Hybrid")
        pickMapStyle("satellite")
        assertMapStyle("Satellite")

        // Leaving the map and opening it again reads the last style from the settings
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["End Round"].waitForExistence(timeout: 5), "The round should still be active")
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Broadlands'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The active round should be listed")
        row.tap()
        XCTAssertTrue(mapStyleButton.waitForExistence(timeout: 5), "The map should open again")
        assertMapStyle("Satellite")
    }
}

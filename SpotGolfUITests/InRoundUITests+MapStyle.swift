import XCTest

/// The map style button and its sheet.
extension InRoundUITests {
    private var mapStyleButton: XCUIElement { app.buttons["MapStyle"] }

    private func assertMapStyle(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let value = mapStyleButton.value as? String ?? ""
        XCTAssertEqual(value, title, "The map button should say \(title), not '\(value)'", file: file, line: line)
    }

    /// Opens the sheet from the map button and picks a style by its identifier suffix.
    private func pickMapStyle(_ choice: String, file: StaticString = #filePath, line: UInt = #line) {
        mapStyleButton.tap()
        let option = app.buttons["MapStyle-\(choice)"]
        XCTAssertTrue(option.waitToExist(), "The sheet should offer \(choice)", file: file, line: line)
        option.tap()
        XCTAssertTrue(option.waitToVanish(), "A pick should close the sheet", file: file, line: line)
    }

    func testTheMapButtonOpensTheSheetAndTheMapOpensWithTheLastPick() throws {
        assertMapStyle("Standard")

        mapStyleButton.tap()
        let standard = app.buttons["MapStyle-standard"]
        XCTAssertTrue(standard.waitToExist(), "The sheet should list the styles")
        XCTAssertTrue(standard.isSelected, "The sheet should mark the current style")
        app.buttons["CloseMapStyles"].tap()
        XCTAssertTrue(standard.waitToVanish(), "Close should close the sheet")
        assertMapStyle("Standard")

        pickMapStyle("hybrid")
        assertMapStyle("Hybrid")
        pickMapStyle("satellite")
        assertMapStyle("Satellite")

        // Leaving the map and opening it again reads the last style from the settings
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["End Round"].waitToExist(), "The round should still be active")
        XCTAssertTrue(broadlandsRow.waitToExist(), "The active round should be listed")
        broadlandsRow.tap()
        XCTAssertTrue(mapStyleButton.waitToExist(), "The map should open again")
        assertMapStyle("Satellite")

        // The other tests expect the standard map
        pickMapStyle("standard")
    }
}

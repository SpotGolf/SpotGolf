import XCTest

/// Adding strokes by hand on the round screen's map.
extension XCUIApplication {
    /// Spots on the map, as fractions of the screen. They stay clear of the header, the key
    /// information boxes and the buttons, and far enough apart that a press never lands on an
    /// earlier stroke.
    static let strokePressPoints: [CGVector] = [0.42, 0.52, 0.62].flatMap { y in
        [0.2, 0.4, 0.6, 0.8].map { x in CGVector(dx: x, dy: y) }
    }

    /// Turns on edit mode if it is off.
    func startEditing() {
        let editButton = buttons["EditHole"]
        if editButton.waitForExistence(timeout: 5), editButton.label == "Edit" {
            editButton.tap()
        }
    }

    /// Long-presses the map, which adds a stroke there and opens its edit sheet.
    /// Strokes can only be added in edit mode, so enter it first when needed.
    func addStroke(at point: CGVector) {
        startEditing()
        let start = coordinate(withNormalizedOffset: point)
        // The map only reports the press once the finger has moved
        start.press(forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 4)))
    }
}

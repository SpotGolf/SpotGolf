import XCTest

/// The hole circles in the round screen's header.
extension XCUIApplication {
    func holeButton(_ number: Int) -> XCUIElement {
        buttons["Hole \(number)"]
    }

    /// Waits until the header marks `number` as the current hole.
    func waitForCurrentHole(_ number: Int, timeout: TimeInterval = 5) -> Bool {
        let current = NSPredicate(format: "exists == true AND selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: current, object: holeButton(number))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Taps a hole's circle and waits for it to become the current hole.
    func goToHole(_ number: Int, file: StaticString = #filePath, line: UInt = #line) {
        let button = holeButton(number)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Hole \(number) circle should exist", file: file, line: line)
        button.tap()
        XCTAssertTrue(waitForCurrentHole(number), "Hole \(number) should become the current hole", file: file, line: line)
    }
}

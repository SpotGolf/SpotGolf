import XCTest

/// The hole circles in the round screen's header.
extension XCUIApplication {
    func holeButton(_ number: Int) -> XCUIElement {
        buttons["Hole \(number)"]
    }

    /// Waits until the header shows `number` as the hole shown.
    func waitForShownHole(_ number: Int, timeout: TimeInterval = UIWait.standard) -> Bool {
        let button = holeButton(number)
        return UIWait.until(timeout: timeout) { button.exists && button.isSelected }
    }

    /// Taps a hole's circle and waits for it to be shown. The header scrolls, so a circle off its
    /// edge is first scrolled into view: a tap there would land on whatever covers it.
    func goToHole(_ number: Int, file: StaticString = #filePath, line: UInt = #line) {
        let button = holeButton(number)
        XCTAssertTrue(button.waitToExist(), "Hole \(number) circle should exist", file: file, line: line)
        // XCTest calls a circle half under the Back button or the score box hittable, so this
        // checks it is clear of both
        let back = buttons["Back"]
        let scoreBox = descendants(matching: .any).matching(identifier: "ScoreBox").firstMatch
        func inView() -> Bool {
            let circle = button.frame
            let left = back.exists ? back.frame.maxX : frame.minX
            let right = scoreBox.exists ? scoreBox.frame.minX : frame.maxX
            return circle.minX >= left && circle.maxX <= right
        }
        for _ in 0..<6 where !inView() {
            let header = coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: button.frame.midY))
            // Drags the circles toward the one wanted
            let toward: CGFloat = button.frame.midX < frame.midX ? 150 : -150
            header.press(forDuration: 0.05, thenDragTo: header.withOffset(CGVector(dx: toward, dy: 0)))
        }
        XCTAssertTrue(inView(), "Hole \(number) circle should scroll into view", file: file, line: line)
        button.tap()
        XCTAssertTrue(waitForShownHole(number), "Hole \(number) should be shown", file: file, line: line)
    }
}

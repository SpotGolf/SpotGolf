import XCTest

/// A spot held by a long press, new or not, follows the finger once it moves, until it lifts, on
/// the map and in Green View.
extension InRoundUITests {
    /// How far a spot that follows the finger stands above it.
    private static let dropLift: CGFloat = 70
    /// A pin's frame ends at the bottom of its dot, this far below the dot's center.
    private static let dotRadius: CGFloat = 4

    func testNewSpotOnTheMapFollowsTheFingerUntilItLifts() throws {
        _ = freshHole()
        // A press with no movement adds the spot under the finger
        let press = app.coordinate(withNormalizedOffset: XCUIApplication.strokePressPoints[0])
        press.press(forDuration: 1.0)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "A held press should add a spot without moving")
        saveInSheet()
        let first = app.buttons["Stroke_1"]
        XCTAssertTrue(first.waitToExist())
        assertDot(of: first, at: press.screenPoint)
        let firstFrame = first.frame

        // Holding a spot without moving it leaves it where it is
        first.press(forDuration: 1.0)
        XCTAssertFalse(app.navigationBars["Edit Spot"].exists, "Holding a spot should not open it")
        XCTAssertLessThan(hypot(first.frame.midX - firstFrame.midX, first.frame.midY - firstFrame.midY), 2,
                          "A held spot the finger did not move should stay where it is")

        let start = app.coordinate(withNormalizedOffset: XCUIApplication.strokePressPoints[5])
        start.press(forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 60, dy: 0)))
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "Lifting the finger should add the spot and open it")
        saveInSheet()

        let second = app.buttons["Stroke_2"]
        XCTAssertTrue(second.waitToExist(), "The dragged spot should be added")
        assertDot(of: second, at: CGPoint(x: start.screenPoint.x + 60, y: start.screenPoint.y - Self.dropLift))
        XCTAssertLessThan(hypot(first.frame.midX - firstFrame.midX, first.frame.midY - firstFrame.midY), 5,
                          "The map should not pan under the drag")

        let pan = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        pan.press(forDuration: 0.05, thenDragTo: pan.withOffset(CGVector(dx: 0, dy: -100)))
        XCTAssertTrue(UIWait.until { abs(first.frame.midY - firstFrame.midY) > 50 }, "The map should pan again")
    }

    func testNewSpotInGreenViewFollowsTheFingerUntilItLifts() throws {
        _ = freshHole()
        app.buttons["GreenView"].tap()
        let ground = element("GreenViewGround")
        XCTAssertTrue(ground.waitToExist(), "Green View should open")
        let pin = element("GreenViewPin")
        XCTAssertTrue(pin.waitToExist())
        let pinFrame = pin.frame

        // Left of center, clear of the flag Green View centers on
        let start = ground.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
        start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: -40, dy: 0)))
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "Lifting the finger should add the spot and open it")
        saveInSheet()

        // The map behind Green View has the spot too
        let spot = ground.buttons["Stroke_1"]
        XCTAssertTrue(spot.waitToExist(), "The dragged spot should be added")
        assertDot(of: spot, at: CGPoint(x: start.screenPoint.x - 40, y: start.screenPoint.y - Self.dropLift))
        // Across only: the flag rises over a spot on the green
        XCTAssertLessThan(abs(pin.frame.midX - pinFrame.midX), 5, "The green should not pan under the drag")

        var before = pin.frame
        let pan = ground.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        pan.press(forDuration: 0.05, thenDragTo: pan.withOffset(CGVector(dx: 0, dy: 100)))
        XCTAssertTrue(UIWait.until { abs(pin.frame.midY - before.midY) > 50 }, "The green should pan again")
        before = pin.frame
        ground.doubleTap()
        XCTAssertTrue(UIWait.until { abs(pin.frame.midY - before.midY) > 50 }, "A double tap should zoom the green")
        before = pin.frame
        ground.pinch(withScale: 0.5, velocity: -1)
        XCTAssertTrue(UIWait.until { abs(pin.frame.midY - before.midY) > 30 }, "A pinch should zoom the green")
        app.buttons["CloseGreenView"].tap()
    }

    /// The spot's dot, at the middle of its pin's bottom edge, is on `point`.
    private func assertDot(of spot: XCUIElement, at point: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        let dot = CGPoint(x: spot.frame.midX, y: spot.frame.maxY - Self.dotRadius)
        XCTAssertEqual(dot.x, point.x, accuracy: 6, "The spot should land where it was dragged", file: file, line: line)
        XCTAssertEqual(dot.y, point.y, accuracy: 6, "The spot should land above the finger", file: file, line: line)
    }
}


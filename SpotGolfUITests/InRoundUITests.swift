import XCTest

/// Everything inside a round, on one round started once at Broadlands. Each test starts on the
/// round screen with no sheet open, and leaves it that way.
///
/// Holes 1 and 2 never get strokes, so tests that read them (par, hazards, the green) see them
/// as a fresh round has them. A test that adds strokes does it on a hole of its own from
/// `freshHole()`.
final class InRoundUITests: UITestGroup {
    /// The next hole no test has used since the round started.
    private static var nextFreshHole = 3

    override func beforeGroup() {
        launch()
        app.startRoundWithCourse()
        Self.nextFreshHole = 3
    }

    /// On the round screen with no sheet or Green View over it: the map style button only
    /// shows then.
    override func isAtGroupStart() -> Bool {
        app.buttons["MapStyle"].exists
    }

    /// Shows a hole no test has used since the round started, and returns its number.
    func freshHole(file: StaticString = #filePath, line: UInt = #line) -> Int {
        let hole = Self.nextFreshHole
        Self.nextFreshHole += 1
        app.goToHole(hole, file: file, line: line)
        return hole
    }

    /// Moves the simulator, and so the player, to a spot.
    func moveTo(latitude: Double, longitude: Double) {
        LocationTestHelper.setSimulatorLocation(latitude: latitude, longitude: longitude)
    }
}

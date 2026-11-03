import XCTest
@testable import SpotGolf

/// One club's shot pattern: its spots of equal chance and its trapezoids. See
/// plans/2026-11-02-caddie-club-and-aim.md, section 2.
final class ShotPatternTests: XCTestCase {
    private let yard = 0.9144
    /// A 7 iron at its starting estimate: 145, from 128 to 157.
    private let sevenIron = ClubDistance(startingDistance: 145, shots: [])

    /// Aimed north from the origin.
    private func pattern(_ distance: ClubDistance, missAngle: Double = 6.4) -> ShotPattern {
        ShotPattern(start: GroundPoint(x: 0, y: 0), heading: .pi / 2, distance: distance, missAngle: missAngle)
    }

    func testTheStandardBellCurve() {
        XCTAssertEqual(BellCurve.inverse(0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(BellCurve.inverse(0.841344746), 1, accuracy: 1e-6)
        XCTAssertEqual(BellCurve.inverse(0.975), 1.959964, accuracy: 1e-6)
        XCTAssertEqual(BellCurve.inverse(0.01), -2.326348, accuracy: 1e-6, "The low tail")
        XCTAssertEqual(BellCurve.inverse(0.99), 2.326348, accuracy: 1e-6, "The high tail")
    }

    func testTheSplitBellCurveHasEachSpreadOnItsSide() {
        let (below, above) = (20.0, 10.0)
        let underPeak = below / (below + above)
        // One standard deviation each side of the peak, on each side's own spread
        let oneBelow = 0.158655254 * 2 * below / (below + above)
        let oneAbove = underPeak + (0.841344746 - 0.5) * 2 * above / (below + above)

        XCTAssertEqual(ShotPattern.splitBellCurve(underPeak, peak: 100, below: below, above: above), 100, accuracy: 1e-6)
        XCTAssertEqual(ShotPattern.splitBellCurve(oneBelow, peak: 100, below: below, above: above), 80, accuracy: 1e-4)
        XCTAssertEqual(ShotPattern.splitBellCurve(oneAbove, peak: 100, below: below, above: above), 110, accuracy: 1e-4)
    }

    func testThereAre121Spots() {
        XCTAssertEqual(pattern(sevenIron).spots.count, 121)
    }

    func testTheSpotsFollowTheSpreadsAndTheMissAngle() {
        let shots = pattern(sevenIron)
        let average = 145 * yard

        XCTAssertEqual(shots.distances.count, 11)
        XCTAssertEqual(shots.distances, shots.distances.sorted())
        XCTAssertLessThan(shots.distances[5], average, "More of the pattern is short than long")
        XCTAssertGreaterThan(average - shots.distances[0], shots.distances[10] - average, "Mishits come up short")
        XCTAssertEqual(shots.angles[5], 0, accuracy: 1e-12)
        XCTAssertEqual(shots.angles[0], -shots.angles[10], accuracy: 1e-12)
        XCTAssertEqual(shots.angles[10], BellCurve.inverse(10.5 / 11) * 6.4 * .pi / 180, accuracy: 1e-12)
    }

    func testEqualSpreadsCenterTheDistancesOnTheAverage() {
        let shots = ShotPattern(start: GroundPoint(x: 0, y: 0), heading: 0, average: 100, shortSpread: 10, longSpread: 10,
                                missAngle: 0.1)

        XCTAssertEqual(shots.distances[5], 100, accuracy: 1e-6)
        XCTAssertEqual(shots.distances[0] + shots.distances[10], 200, accuracy: 1e-6)
    }

    func testTheAimPointIsTheAverageAlongTheAim() {
        let aim = pattern(sevenIron).aimPoint

        XCTAssertEqual(aim.x, 0, accuracy: 1e-9)
        XCTAssertEqual(aim.y, 145 * yard, accuracy: 1e-9)
    }

    func testTheTrapezoidsMatchThePlansExamples() {
        let shots = pattern(sevenIron)
        func widths(_ k: Double) -> (near: Double, far: Double, nearDistance: Double, farDistance: Double) {
            let corners = shots.corners(k: k)
            return (corners[0].distance(to: corners[1]) / yard, corners[3].distance(to: corners[2]) / yard,
                    corners[0].y / yard, corners[3].y / yard)
        }

        let one = widths(1)
        XCTAssertEqual(one.nearDistance, 128, accuracy: 1e-6)
        XCTAssertEqual(one.farDistance, 157, accuracy: 1e-6)
        XCTAssertEqual(one.near, 28.7, accuracy: 0.1)
        XCTAssertEqual(one.far, 35.2, accuracy: 0.1)

        let two = widths(2)
        XCTAssertEqual(two.nearDistance, 111, accuracy: 1e-6)
        XCTAssertEqual(two.farDistance, 169, accuracy: 1e-6)
        XCTAssertEqual(two.near, 50.4, accuracy: 0.1)
        XCTAssertEqual(two.far, 76.8, accuracy: 0.1)
    }

    func testTheTrapezoidsCornersGoLeftThenRight() {
        // Aimed north, left is west
        let corners = pattern(sevenIron).corners(k: 1)

        XCTAssertLessThan(corners[0].x, 0)
        XCTAssertGreaterThan(corners[1].x, 0)
        XCTAssertGreaterThan(corners[2].x, 0)
        XCTAssertLessThan(corners[3].x, 0)
    }

    func testRightOfTheAimIsClockwise() {
        // Aimed north, the last angle is right of the aim: east
        let shots = pattern(sevenIron)
        let rightmost = shots.spots.suffix(11)

        XCTAssertTrue(rightmost.allSatisfy { $0.x > 0 })
    }
}

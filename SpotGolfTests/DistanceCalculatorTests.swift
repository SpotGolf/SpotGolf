import XCTest
import CoreLocation
@testable import SpotGolf

final class DistanceCalculatorTests: XCTestCase {

    func testYardsBetweenSamePoint() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(coordinate: coord)

        let yards = DistanceCalculator.yards(from: mark, to: mark)
        XCTAssertEqual(yards, 0, accuracy: 0.1)
    }

    func testYardsBetweenKnownPoints() {
        // Two points approximately 100 meters apart (north-south at equator)
        let markA = BallMark(coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0))
        let markB = BallMark(coordinate: CLLocationCoordinate2D(latitude: 0.0009, longitude: 0.0))

        let yards = DistanceCalculator.yards(from: markA, to: markB)

        // 0.0009 degrees latitude ≈ 100 meters ≈ 109 yards
        XCTAssertGreaterThan(yards, 90)
        XCTAssertLessThan(yards, 130)
    }

    func testYardsIsPositive() {
        let markA = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markB = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.46, longitude: -112.07))

        let yards = DistanceCalculator.yards(from: markA, to: markB)
        XCTAssertGreaterThan(yards, 0)
    }

    func testYardsIsSymmetric() {
        let markA = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markB = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.46, longitude: -112.08))

        let ab = DistanceCalculator.yards(from: markA, to: markB)
        let ba = DistanceCalculator.yards(from: markB, to: markA)

        XCTAssertEqual(ab, ba, accuracy: 0.1)
    }

    func testFormattedYardsContainsYds() {
        let markA = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markB = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.46, longitude: -112.07))

        let formatted = DistanceCalculator.formattedYards(from: markA, to: markB)
        XCTAssertTrue(formatted.hasSuffix(" yds"))
    }

    func testFormattedYardsZeroDistance() {
        let coord = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let mark = BallMark(coordinate: coord)

        let formatted = DistanceCalculator.formattedYards(from: mark, to: mark)
        XCTAssertEqual(formatted, "0 yds")
    }

    func testFormattedYardsIsWholeNumber() {
        let markA = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        let markB = BallMark(coordinate: CLLocationCoordinate2D(latitude: 33.46, longitude: -112.07))

        let formatted = DistanceCalculator.formattedYards(from: markA, to: markB)
        // Should be like "1214 yds" — no decimal point
        let numberPart = formatted.replacingOccurrences(of: " yds", with: "")
        XCTAssertNotNil(Int(numberPart), "Expected whole number, got: \(numberPart)")
    }
}

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

    // MARK: - CLLocation overloads

    func testYardsFromCLLocations() {
        let a = CLLocation(latitude: 33.45, longitude: -112.07)
        let b = CLLocation(latitude: 33.46, longitude: -112.07)

        let yards = DistanceCalculator.yards(from: a, to: b)
        XCTAssertGreaterThan(yards, 0)
    }

    func testYardsFromCLLocationsMatchesBallMarkOverload() {
        let coordA = CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07)
        let coordB = CLLocationCoordinate2D(latitude: 33.46, longitude: -112.08)
        let markA = BallMark(coordinate: coordA)
        let markB = BallMark(coordinate: coordB)

        let fromMarks = DistanceCalculator.yards(from: markA, to: markB)
        let fromLocations = DistanceCalculator.yards(from: markA.location, to: markB.location)

        XCTAssertEqual(fromMarks, fromLocations, accuracy: 0.01)
    }

    func testFormattedYardsFromCLLocations() {
        let a = CLLocation(latitude: 33.45, longitude: -112.07)
        let b = CLLocation(latitude: 33.46, longitude: -112.07)

        let formatted = DistanceCalculator.formattedYards(from: a, to: b)
        XCTAssertTrue(formatted.hasSuffix(" yds"))
    }

    func testFormattedYardsFromCLLocationsZeroDistance() {
        let location = CLLocation(latitude: 33.45, longitude: -112.07)

        let formatted = DistanceCalculator.formattedYards(from: location, to: location)
        XCTAssertEqual(formatted, "0 yds")
    }

    // MARK: - Green distances

    func testDistancesToGreen() {
        // Player is south of a green that runs south-to-north (front closest, back farthest)
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)

        let green = CourseGreen(
            front: CourseCoordinate(latitude: 33.4420, longitude: -112.07),
            middle: CourseCoordinate(latitude: 33.4425, longitude: -112.07),
            back: CourseCoordinate(latitude: 33.4430, longitude: -112.07)
        )

        let distances = DistanceCalculator.greenDistances(from: playerLocation, green: green)

        XCTAssertLessThan(distances.front, distances.middle)
        XCTAssertLessThan(distances.middle, distances.back)
        XCTAssertGreaterThan(distances.front, 0)
    }

    // MARK: - Features ahead

    func testFeaturesAhead() {
        // Player at south, green to the north
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)

        let green = CourseGreen(
            front: CourseCoordinate(latitude: 33.4450, longitude: -112.07),
            middle: CourseCoordinate(latitude: 33.4455, longitude: -112.07),
            back: CourseCoordinate(latitude: 33.4460, longitude: -112.07)
        )

        // Bunker ahead (between player and green)
        let bunkerAhead = CourseFeature(
            id: "bunker-ahead",
            type: .bunker,
            front: CourseCoordinate(latitude: 33.4420, longitude: -112.07),
            back: CourseCoordinate(latitude: 33.4425, longitude: -112.07)
        )

        // Bunker behind player (south of player)
        let bunkerBehind = CourseFeature(
            id: "bunker-behind",
            type: .bunker,
            front: CourseCoordinate(latitude: 33.4380, longitude: -112.07),
            back: CourseCoordinate(latitude: 33.4385, longitude: -112.07)
        )

        let result = DistanceCalculator.featuresAhead(
            from: playerLocation,
            features: [bunkerAhead, bunkerBehind],
            green: green
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.feature.id, "bunker-ahead")
        XCTAssertGreaterThan(result.first?.distanceYards ?? 0, 0)
    }

    func testFeaturesAheadSortedByDistance() {
        // Player at south, green to the north
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)

        let green = CourseGreen(
            front: CourseCoordinate(latitude: 33.4460, longitude: -112.07),
            middle: CourseCoordinate(latitude: 33.4465, longitude: -112.07),
            back: CourseCoordinate(latitude: 33.4470, longitude: -112.07)
        )

        // Closer feature
        let closerBunker = CourseFeature(
            id: "bunker-close",
            type: .bunker,
            front: CourseCoordinate(latitude: 33.4410, longitude: -112.07),
            back: CourseCoordinate(latitude: 33.4415, longitude: -112.07)
        )

        // Farther feature
        let fartherWater = CourseFeature(
            id: "water-far",
            type: .water,
            front: CourseCoordinate(latitude: 33.4435, longitude: -112.07),
            back: CourseCoordinate(latitude: 33.4440, longitude: -112.07)
        )

        let result = DistanceCalculator.featuresAhead(
            from: playerLocation,
            features: [fartherWater, closerBunker],  // intentionally out of order
            green: green
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].feature.id, "bunker-close")
        XCTAssertEqual(result[1].feature.id, "water-far")
        XCTAssertLessThan(result[0].distanceYards, result[1].distanceYards)
    }
}

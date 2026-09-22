import XCTest
import CoreLocation
import CourseDataSwift
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
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4420, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0695),
            Coordinate(latitude: 33.4430, longitude: -112.0695),
            Coordinate(latitude: 33.4430, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0705),
        ])
        let direction = Vector2D(dx: 1, dy: 0).normalized()
        let distances = DistanceCalculator.greenDistances(from: playerLocation, green: green, direction: direction)
        XCTAssertLessThan(distances.front, distances.middle)
        XCTAssertLessThan(distances.middle, distances.back)
        XCTAssertGreaterThan(distances.front, 0)
    }

    func testDistancesToGreenNegativeWhenPast() {
        // Player is north of the green (past the back)
        let playerLocation = CLLocation(latitude: 33.4435, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4420, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0695),
            Coordinate(latitude: 33.4430, longitude: -112.0695),
            Coordinate(latitude: 33.4430, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0705),
        ])
        // Direction of play: south to north
        let direction = Vector2D(dx: 1, dy: 0).normalized()
        let distances = DistanceCalculator.greenDistances(from: playerLocation, green: green, direction: direction)

        // Player is past all three points — all should be negative
        XCTAssertLessThan(distances.front, 0)
        XCTAssertLessThan(distances.middle, 0)
        XCTAssertLessThan(distances.back, 0)
    }

    func testDistancesToGreenPartiallyPast() {
        // Player is on the green, past the front but before the back
        let playerLocation = CLLocation(latitude: 33.4425, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4420, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0695),
            Coordinate(latitude: 33.4430, longitude: -112.0695),
            Coordinate(latitude: 33.4430, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0705),
        ])
        let direction = Vector2D(dx: 1, dy: 0).normalized()
        let distances = DistanceCalculator.greenDistances(from: playerLocation, green: green, direction: direction)

        // Past the front, at/near middle, before the back
        XCTAssertLessThan(distances.front, 0)
        XCTAssertGreaterThan(distances.back, 0)
    }

    // MARK: - Features ahead

    func testFeaturesAhead() {
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4450, longitude: -112.0705),
            Coordinate(latitude: 33.4450, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0705),
            Coordinate(latitude: 33.4450, longitude: -112.0705),
        ])
        let bunkerAhead = Feature(id: 2, type: .bunker, polygon: [
            Coordinate(latitude: 33.4420, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0695),
            Coordinate(latitude: 33.4425, longitude: -112.0695),
            Coordinate(latitude: 33.4425, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0705),
        ])
        let bunkerBehind = Feature(id: 3, type: .bunker, polygon: [
            Coordinate(latitude: 33.4380, longitude: -112.0705),
            Coordinate(latitude: 33.4380, longitude: -112.0695),
            Coordinate(latitude: 33.4385, longitude: -112.0695),
            Coordinate(latitude: 33.4385, longitude: -112.0705),
            Coordinate(latitude: 33.4380, longitude: -112.0705),
        ])
        let result = DistanceCalculator.featuresAhead(from: playerLocation, features: [bunkerAhead, bunkerBehind], green: green)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.feature.id, 2)
        XCTAssertGreaterThan(result.first?.distanceYards ?? 0, 0)
    }

    func testFeaturesAheadReportsWhereTheHazardStarts() throws {
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4450, longitude: -112.0705),
            Coordinate(latitude: 33.4450, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0705),
        ])
        let bunker = Feature(id: 2, type: .bunker, polygon: [
            Coordinate(latitude: 33.4420, longitude: -112.0705),
            Coordinate(latitude: 33.4420, longitude: -112.0695),
            Coordinate(latitude: 33.4425, longitude: -112.0695),
            Coordinate(latitude: 33.4425, longitude: -112.0705),
        ])

        let hazard = try XCTUnwrap(DistanceCalculator.featuresAhead(from: playerLocation, features: [bunker], green: green).first)

        // The player is due south, so the hazard starts at a corner of its south edge
        XCTAssertTrue(bunker.polygon.contains(hazard.nearestPoint))
        XCTAssertEqual(hazard.nearestPoint.latitude, 33.4420, accuracy: 0.00001)
        let yards = DistanceCalculator.yards(from: playerLocation, to: hazard.nearestPoint.clLocation)
        XCTAssertEqual(Double(hazard.distanceYards), yards, accuracy: 1)
        XCTAssertEqual(hazard.id, 2)
    }

    func testFeaturesAheadExcludesOffLineFeatures() {
        // Player at south, green to the north
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4450, longitude: -112.0705),
            Coordinate(latitude: 33.4450, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0705),
            Coordinate(latitude: 33.4450, longitude: -112.0705),
        ])
        // Bunker ahead and in line — should be included
        let bunkerInLine = Feature(id: 2, type: .bunker, polygon: [
            Coordinate(latitude: 33.4420, longitude: -112.0702),
            Coordinate(latitude: 33.4420, longitude: -112.0698),
            Coordinate(latitude: 33.4425, longitude: -112.0698),
            Coordinate(latitude: 33.4425, longitude: -112.0702),
            Coordinate(latitude: 33.4420, longitude: -112.0702),
        ])
        // Bunker ahead in distance but far off to the side (>45° off line)
        let bunkerOffLine = Feature(id: 3, type: .bunker, polygon: [
            Coordinate(latitude: 33.4410, longitude: -112.0760),
            Coordinate(latitude: 33.4410, longitude: -112.0750),
            Coordinate(latitude: 33.4415, longitude: -112.0750),
            Coordinate(latitude: 33.4415, longitude: -112.0760),
            Coordinate(latitude: 33.4410, longitude: -112.0760),
        ])
        let result = DistanceCalculator.featuresAhead(from: playerLocation, features: [bunkerInLine, bunkerOffLine], green: green)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.feature.id, 2)
    }

    func testFeaturesAheadLimitedToThree() {
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4470, longitude: -112.0705),
            Coordinate(latitude: 33.4470, longitude: -112.0695),
            Coordinate(latitude: 33.4480, longitude: -112.0695),
            Coordinate(latitude: 33.4480, longitude: -112.0705),
            Coordinate(latitude: 33.4470, longitude: -112.0705),
        ])
        // 5 bunkers ahead of player, between player and green
        let bunkers = (0..<5).map { i in
            let lat = 33.4410 + Double(i) * 0.001
            return Feature(id: 2 + i, type: .bunker, polygon: [
                Coordinate(latitude: lat, longitude: -112.0705),
                Coordinate(latitude: lat, longitude: -112.0695),
                Coordinate(latitude: lat + 0.0005, longitude: -112.0695),
                Coordinate(latitude: lat + 0.0005, longitude: -112.0705),
                Coordinate(latitude: lat, longitude: -112.0705),
            ])
        }
        let result = DistanceCalculator.featuresAhead(from: playerLocation, features: bunkers, green: green)
        XCTAssertEqual(result.count, 3)
    }

    func testFeaturesAheadCustomLimit() {
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4470, longitude: -112.0705),
            Coordinate(latitude: 33.4470, longitude: -112.0695),
            Coordinate(latitude: 33.4480, longitude: -112.0695),
            Coordinate(latitude: 33.4480, longitude: -112.0705),
            Coordinate(latitude: 33.4470, longitude: -112.0705),
        ])
        // 5 bunkers ahead of player, between player and green
        let bunkers = (0..<5).map { i in
            let lat = 33.4410 + Double(i) * 0.001
            return Feature(id: 2 + i, type: .bunker, polygon: [
                Coordinate(latitude: lat, longitude: -112.0705),
                Coordinate(latitude: lat, longitude: -112.0695),
                Coordinate(latitude: lat + 0.0005, longitude: -112.0695),
                Coordinate(latitude: lat + 0.0005, longitude: -112.0705),
                Coordinate(latitude: lat, longitude: -112.0705),
            ])
        }
        let result = DistanceCalculator.featuresAhead(from: playerLocation, features: bunkers, green: green, limit: 5)
        XCTAssertEqual(result.count, 5)
    }

    func testFeaturesAheadEmptyWhenOnGreen() {
        // Player standing on the green
        let playerLocation = CLLocation(latitude: 33.4455, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4450, longitude: -112.0705),
            Coordinate(latitude: 33.4450, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0695),
            Coordinate(latitude: 33.4460, longitude: -112.0705),
            Coordinate(latitude: 33.4450, longitude: -112.0705),
        ])
        let bunker = Feature(id: 2, type: .bunker, polygon: [
            Coordinate(latitude: 33.4445, longitude: -112.0705),
            Coordinate(latitude: 33.4445, longitude: -112.0695),
            Coordinate(latitude: 33.4448, longitude: -112.0695),
            Coordinate(latitude: 33.4448, longitude: -112.0705),
            Coordinate(latitude: 33.4445, longitude: -112.0705),
        ])
        let result = DistanceCalculator.featuresAhead(from: playerLocation, features: [bunker], green: green)
        XCTAssertTrue(result.isEmpty)
    }

    func testFeaturesAheadSortedByDistance() {
        let playerLocation = CLLocation(latitude: 33.4400, longitude: -112.07)
        let green = Feature(id: 1, type: .green, polygon: [
            Coordinate(latitude: 33.4460, longitude: -112.0705),
            Coordinate(latitude: 33.4460, longitude: -112.0695),
            Coordinate(latitude: 33.4470, longitude: -112.0695),
            Coordinate(latitude: 33.4470, longitude: -112.0705),
            Coordinate(latitude: 33.4460, longitude: -112.0705),
        ])
        let closerBunker = Feature(id: 2, type: .bunker, polygon: [
            Coordinate(latitude: 33.4410, longitude: -112.0705),
            Coordinate(latitude: 33.4410, longitude: -112.0695),
            Coordinate(latitude: 33.4415, longitude: -112.0695),
            Coordinate(latitude: 33.4415, longitude: -112.0705),
            Coordinate(latitude: 33.4410, longitude: -112.0705),
        ])
        let fartherWater = Feature(id: 3, type: .water, polygon: [
            Coordinate(latitude: 33.4435, longitude: -112.0705),
            Coordinate(latitude: 33.4435, longitude: -112.0695),
            Coordinate(latitude: 33.4440, longitude: -112.0695),
            Coordinate(latitude: 33.4440, longitude: -112.0705),
            Coordinate(latitude: 33.4435, longitude: -112.0705),
        ])
        let result = DistanceCalculator.featuresAhead(from: playerLocation, features: [fartherWater, closerBunker], green: green)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].feature.id, 2)
        XCTAssertEqual(result[1].feature.id, 3)
        XCTAssertLessThan(result[0].distanceYards, result[1].distanceYards)
    }
}

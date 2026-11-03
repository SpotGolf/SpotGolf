import XCTest
@testable import SpotGolf

/// A club's starting estimate from the bag, and how its shots move it. See
/// plans/2026-11-02-caddie-club-distances.md, section 3.
final class ClubDistanceTests: XCTestCase {
    func testNoShotsGivesTheStartingEstimate() {
        let driver = ClubDistance(startingDistance: 230, shots: [])
        XCTAssertEqual([driver.average, driver.low, driver.high, driver.shots], [230, 202, 248, 0])

        let sevenIron = ClubDistance(startingDistance: 145, shots: [])
        XCTAssertEqual([sevenIron.low, sevenIron.high], [128, 157])
    }

    func testTheAverageMovesTowardTheShots() {
        let averages = [5, 20, 50].map { ClubDistance(startingDistance: 230, shots: Array(repeating: 256, count: $0)).average }

        XCTAssertEqual(averages, [243, 251, 254])
    }

    func testEachSpreadComesFromTheShotsOnItsSide() {
        // The average stays at 230, with one shot 30 yards each side of it
        let distance = ClubDistance(startingDistance: 230, shots: [200, 260])

        XCTAssertEqual([distance.average, distance.low, distance.high, distance.shots], [230, 202, 252, 2])
    }

    func testSteadyShotsNarrowTheRange() {
        let distance = ClubDistance(startingDistance: 230, shots: Array(repeating: 230, count: 100))

        XCTAssertEqual([distance.low, distance.high], [224, 234])
    }

    func testAMishitWidensTheShortSide() {
        let distance = ClubDistance(startingDistance: 145, shots: [60])

        XCTAssertEqual([distance.average, distance.low, distance.high], [131, 87, 141])
    }
}

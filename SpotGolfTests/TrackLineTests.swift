import XCTest
import CoreLocation
@testable import SpotGolf

final class TrackLineTests: XCTestCase {

    /// Fixes a second apart, each `meters` north of the first.
    private func track(metersNorth: [Double]) -> [TrackPoint] {
        metersNorth.enumerated().map { index, meters in
            // A degree of latitude is about 111,320 m
            TrackPoint(timestamp: Date(timeIntervalSince1970: Double(index)),
                       latitude: 39.0 + meters / 111_320, longitude: -105.0, altitude: nil)
        }
    }

    func testEmptyTrackHasNoLine() {
        XCTAssertTrue(TrackLine.coordinates(of: []).isEmpty)
    }

    func testKeepsTheFirstFixAndEachOneFarEnoughFromTheLastKept() {
        // Walking north 1.1 m a second: kept at 0, 3.3, 6.6 and 9.9 m
        let line = TrackLine.coordinates(of: track(metersNorth: (0..<10).map { Double($0) * 1.1 }))

        XCTAssertEqual(line.count, 4)
        XCTAssertEqual(line.map(\.latitude), [0, 3.3, 6.6, 9.9].map { 39.0 + $0 / 111_320 }, accuracy: 1e-9)
    }

    func testDriftWhileStandingStillIsOneFix() {
        // Fixes wandering within 1 m of the first
        let drift = track(metersNorth: [0, 0.4, -0.5, 0.9, 0.1, -0.8, 0.3, 0.7, -0.2, 0.6])

        XCTAssertEqual(TrackLine.coordinates(of: drift).count, 1)
    }

    func testSpacingCanBeChosen() {
        let fixes = track(metersNorth: (0..<10).map { Double($0) * 1.1 })

        // Kept at 0, 2.2, 4.4, 6.6 and 8.8 m
        XCTAssertEqual(TrackLine.coordinates(of: fixes, minimumSpacing: 2).count, 5)
    }
}

private func XCTAssertEqual(_ values: [Double], _ expected: [Double], accuracy: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(values.count, expected.count, file: file, line: line)
    for (value, expectedValue) in zip(values, expected) {
        XCTAssertEqual(value, expectedValue, accuracy: accuracy, file: file, line: line)
    }
}

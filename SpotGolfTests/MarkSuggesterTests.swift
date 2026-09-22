import XCTest
import CoreLocation
@testable import SpotGolf

final class MarkSuggesterTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let baseLat = 39.9555
    private let baseLon = -105.0422

    /// Degrees of latitude for a distance in meters.
    private func latDegrees(_ meters: Double) -> Double {
        meters / 111_320.0
    }

    /// Points every 5 seconds at one spot.
    private func dwell(latOffset: Double = 0, from: TimeInterval, seconds: TimeInterval) -> [TrackPoint] {
        stride(from: from, through: from + seconds, by: 5).map {
            TrackPoint(timestamp: start.addingTimeInterval($0),
                       latitude: baseLat + latOffset, longitude: baseLon, altitude: nil)
        }
    }

    /// Points every 5 seconds moving steadily north, about 10 meters per point.
    private func walk(latOffset: Double = 0, from: TimeInterval, count: Int) -> [TrackPoint] {
        (0..<count).map { i in
            TrackPoint(timestamp: start.addingTimeInterval(from + Double(i) * 5),
                       latitude: baseLat + latOffset + latDegrees(Double(i) * 10),
                       longitude: baseLon, altitude: nil)
        }
    }

    func testDwellCreatesSuggestion() throws {
        let dwellOffset = latDegrees(200)
        let points = walk(from: 0, count: 10)
            + dwell(latOffset: dwellOffset, from: 60, seconds: 45)
            + walk(latOffset: dwellOffset + latDegrees(30), from: 110, count: 10)

        let suggestions = MarkSuggester.suggestions(in: points, minDwell: 30, marks: [])

        XCTAssertEqual(suggestions.count, 1)
        let suggestion = try XCTUnwrap(suggestions.first)
        XCTAssertEqual(suggestion.latitude, baseLat + dwellOffset, accuracy: latDegrees(1))
        XCTAssertEqual(suggestion.longitude, baseLon, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(suggestion.duration, 30)
        XCTAssertNil(suggestion.guessID)
    }

    func testMovingTrackHasNoSuggestions() {
        let points = walk(from: 0, count: 60)
        XCTAssertTrue(MarkSuggester.suggestions(in: points, minDwell: 30, marks: []).isEmpty)
    }

    func testZeroThresholdIsFlooredAndDoesNotSpamSuggestions() {
        let points = walk(from: 0, count: 60)
        XCTAssertTrue(MarkSuggester.suggestions(in: points, minDwell: 0, marks: []).isEmpty)
    }

    func testShortDwellIsIgnored() {
        let points = walk(from: 0, count: 5)
            + dwell(latOffset: latDegrees(100), from: 25, seconds: 15)
            + walk(latOffset: latDegrees(150), from: 45, count: 5)
        XCTAssertTrue(MarkSuggester.suggestions(in: points, minDwell: 30, marks: []).isEmpty)
    }

    func testDwellNearExistingMarkIsDropped() {
        let dwellOffset = latDegrees(200)
        let points = walk(from: 0, count: 10)
            + dwell(latOffset: dwellOffset, from: 60, seconds: 45)
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: baseLat + dwellOffset + latDegrees(5),
                                                               longitude: baseLon))

        XCTAssertTrue(MarkSuggester.suggestions(in: points, minDwell: 30, marks: [mark]).isEmpty)
    }

    func testGuessBecomesSuggestionAndDedupesOverlappingDwell() {
        let dwellOffset = latDegrees(200)
        let points = dwell(latOffset: dwellOffset, from: 0, seconds: 45)
        let guess = MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: baseLat + dwellOffset, longitude: baseLon),
            timestamp: start,
            holeIndex: 0, reason: .stationary, roundID: UUID()
        )

        let suggestions = MarkSuggester.suggestions(in: points, minDwell: 30, marks: [], guesses: [guess])

        XCTAssertEqual(suggestions.count, 1, "The dwell overlaps the guess and should be dropped as a duplicate")
        XCTAssertEqual(suggestions.first?.guessID, guess.id)
    }

    func testGuessNearMarkIsDropped() {
        let guess = MissedMarkGuess(
            coordinate: CLLocationCoordinate2D(latitude: baseLat, longitude: baseLon),
            timestamp: start,
            holeIndex: 0, reason: .swing, roundID: UUID()
        )
        let mark = BallMark(coordinate: CLLocationCoordinate2D(latitude: baseLat + latDegrees(5),
                                                               longitude: baseLon))

        XCTAssertTrue(MarkSuggester.suggestions(in: [], minDwell: 30, marks: [mark], guesses: [guess]).isEmpty)
    }

    func testSuggestionsAreInTimeOrder() {
        let firstOffset = latDegrees(100)
        let secondOffset = latDegrees(300)
        let points = dwell(latOffset: firstOffset, from: 0, seconds: 45)
            + walk(latOffset: firstOffset + latDegrees(20), from: 50, count: 10)
            + dwell(latOffset: secondOffset, from: 120, seconds: 45)

        let suggestions = MarkSuggester.suggestions(in: points, minDwell: 30, marks: [])

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertLessThan(suggestions[0].timestamp, suggestions[1].timestamp)
        XCTAssertEqual(suggestions[0].latitude, baseLat + firstOffset, accuracy: latDegrees(1))
        XCTAssertEqual(suggestions[1].latitude, baseLat + secondOffset, accuracy: latDegrees(1))
    }

    func testHolePointsWithoutCourseReturnsEverything() {
        let points = walk(from: 0, count: 10)
        XCTAssertEqual(MarkSuggester.holePoints(in: points, holeIndex: 3, courseSelection: nil), points)
    }
}

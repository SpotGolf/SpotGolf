import CoreLocation
import XCTest
@testable import SpotGolf

/// The miss angle from the player's average score. See plans/2026-11-02-caddie-club-and-aim.md,
/// section 2.
@MainActor
final class MissAngleTests: XCTestCase {
    private func stroke(penaltyStrokes: Int = 0) -> Stroke {
        Stroke(coordinate: CLLocationCoordinate2D(latitude: 39, longitude: -105), penaltyStrokes: penaltyStrokes)
    }

    /// A round with one hole of `strokes` strokes for each count in `holes`.
    private func round(_ holes: [Int], status: RoundStatus = .ended) -> Round {
        let round = Round(status: status, courseSelection: .test)
        round.holes = holes.map { RoundHole(strokes: Array(repeating: stroke(), count: $0)) }
        return round
    }

    func testNoRoundsGiveTheStartingAngle() {
        XCTAssertEqual(MissAngle.degrees(for: []), 6.4)
        XCTAssertEqual(MissAngle.degrees(averageScore: nil), 6.4)
    }

    func testRunsThroughThe80And100Golfers() {
        XCTAssertEqual(MissAngle.degrees(averageScore: 80), 5.5, accuracy: 1e-9)
        XCTAssertEqual(MissAngle.degrees(averageScore: 100), 7.9, accuracy: 1e-9)
        XCTAssertEqual(MissAngle.degrees(averageScore: 87.5), 6.4, accuracy: 1e-9, "Broadie's 84 to 97 group")
    }

    func testStaysInsideThePublishedRange() {
        XCTAssertEqual(MissAngle.degrees(averageScore: 70), 5.4)
        XCTAssertEqual(MissAngle.degrees(averageScore: 125), 8.1)
    }

    func testANineHoleRoundCountsAt18Holes() throws {
        // 9 holes of 5: 90 over 18
        let average = try XCTUnwrap(MissAngle.averageScore(of: [round(Array(repeating: 5, count: 9))]))

        XCTAssertEqual(average, 90, accuracy: 1e-9)
        XCTAssertEqual(MissAngle.degrees(for: [round(Array(repeating: 5, count: 9))]), 6.7, accuracy: 1e-9)
    }

    func testHolesWithoutStrokesAreLeftOut() throws {
        let average = try XCTUnwrap(MissAngle.averageScore(of: [round([4, 6, 0, 0])]))

        XCTAssertEqual(average, 90, accuracy: 1e-9)
    }

    func testPenaltyStrokesCount() throws {
        let played = round([4])
        played.holes[0].strokes[0] = stroke(penaltyStrokes: 1)

        XCTAssertEqual(try XCTUnwrap(MissAngle.averageScore(of: [played])), 18 * 5, accuracy: 1e-9)
    }

    func testOnlyEndedRoundsCount() {
        XCTAssertNil(MissAngle.averageScore(of: [round([9], status: .active), round([9], status: .ending)]))
    }
}

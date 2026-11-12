import CourseDataSwift
import XCTest
@testable import SpotGolf

/// The chance of a shot stopping on each lie, on made-up holes. See
/// plans/2026-11-11-shot-dispersion.md, section 8.
@MainActor
final class DispersionOutcomesTests: XCTestCase {
    /// A 7 iron from the middle group, aimed north from the tee.
    private let params = DispersionParams.forApproach(missAngle: 6.4, yards: 145)
    private let fairway: (FeatureType, [Coordinate]) = (.fairway, PlayCourse.rectangle(north: 20...110, east: -20...20))

    private func outcomes(_ features: [(FeatureType, [Coordinate])]) -> DispersionOutcomes {
        // The green is 30 m square, around the 7 iron's 133 m
        let lies = PlayCourse.lies(PlayCourse.selection(greenNorth: 133, features: features))
        return DispersionOutcomes(shots: DispersionModel.sample(params, n: 2_000, seed: 7),
                                  start: GroundPoint(x: 0, y: 0), heading: .pi / 2, lies: lies)
    }

    func testTheChancesAddToOne() {
        let outcomes = outcomes([fairway])

        XCTAssertEqual(outcomes.fairway + outcomes.rough + outcomes.sand + outcomes.water + outcomes.green, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(outcomes.green, 0.3, "Aimed at the middle of the green")
        XCTAssertGreaterThan(outcomes.fairway, 0.05, "Mishits stop short, on the fairway")
        XCTAssertEqual(outcomes.hazard, 0)
        XCTAssertEqual(outcomes.fairwayOrGreen, outcomes.fairway + outcomes.green)
    }

    func testWaterBesideTheGreenTakesItsShare() {
        let dry = outcomes([fairway])
        let water: (FeatureType, [Coordinate]) = (.water, PlayCourse.rectangle(north: 100...170, east: -80...(-15)))
        let wet = outcomes([fairway, water])

        XCTAssertGreaterThan(wet.water, 0.1)
        XCTAssertEqual(wet.hazard, wet.water)
        XCTAssertEqual(wet.rough, dry.rough - wet.water, accuracy: 0.02, "The water was rough")
        XCTAssertEqual(wet.green, dry.green, accuracy: 1e-9)
    }

    func testTheSummaryCountsTheGreenAloneWhenAimedAtIt() throws {
        var outcomes = DispersionOutcomes(shots: [], start: GroundPoint(x: 0, y: 0), heading: 0,
                                          lies: PlayCourse.lies(PlayCourse.selection(greenNorth: 133)))
        outcomes.fairway = 0.2
        outcomes.green = 0.4
        outcomes.sand = 0.05
        outcomes.water = 0.011
        let club = try XCTUnwrap(Club.named("7i"))
        let shot = CaddieShot(club: club, yards: 145, params: params,
                              spots: ShotSpots(params, start: GroundPoint(x: 0, y: 0), heading: .pi / 2),
                              plane: PlayCourse.plane)

        XCTAssertEqual(CaddieStats(shot: shot, outcomes: outcomes, aimsAtGreen: false).summary, "60% fairway · 6% hazard")
        XCTAssertEqual(CaddieStats(shot: shot, outcomes: outcomes, aimsAtGreen: true).summary, "40% green · 6% hazard")
        XCTAssertEqual(CaddieStats(shot: shot, outcomes: outcomes, aimsAtGreen: false).spokenSummary,
                       "Caddie: 7 Iron, 60% fairway or green, 6% hazard")
    }
}

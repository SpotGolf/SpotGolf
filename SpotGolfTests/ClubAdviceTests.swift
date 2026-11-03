import CourseDataSwift
import XCTest
@testable import SpotGolf

/// The club and aim the Caddie picks, on made-up holes. See
/// plans/2026-11-02-caddie-club-and-aim.md, section 3.
@MainActor
final class ClubAdviceTests: XCTestCase {
    /// Each club at its starting estimate from `yards`.
    private func clubs(_ yards: [(String, Int)]) -> [(club: Club, distance: ClubDistance)] {
        yards.map { (club: Club.named($0.0)!, distance: ClubDistance(startingDistance: $0.1, shots: [])) }
    }

    private let irons = [("3w", 215), ("3h", 190), ("5i", 165), ("7i", 145), ("9i", 125), ("pw", 115)]

    /// From hole 1's tee to its pin, the green's center.
    private func best(_ selection: CourseSelection, greenNorth: Double, clubs: [(club: Club, distance: ClubDistance)],
                      from start: GroundPoint = GroundPoint(x: 0, y: 0)) throws -> ClubAdvice {
        try XCTUnwrap(ClubAdvice.best(from: start, pin: GroundPoint(x: 0, y: greenNorth), clubs: clubs,
                                      missAngle: 6.4, lies: PlayCourse.lies(selection)))
    }

    private let fairway: (FeatureType, [Coordinate]) = (.fairway, PlayCourse.rectangle(north: 20...140, east: -20...20))

    func testOpenGroundAimsAtThePinWithTheClubThatReachesIt() throws {
        // 164 yards to the pin
        let advice = try best(PlayCourse.selection(greenNorth: 150, features: [fairway]), greenNorth: 150,
                              clubs: clubs(irons))

        XCTAssertEqual(advice.club.id, "5i")
        XCTAssertEqual(advice.aimOffset, 0, "Either side scores the same, and the tie goes to the pin line")
        XCTAssertEqual(advice.yards, 165)
    }

    func testWaterLeftOfTheGreenMovesTheAimRight() throws {
        let water: (FeatureType, [Coordinate]) = (.water, PlayCourse.rectangle(north: 100...200, east: -80...(-17)))
        let advice = try best(PlayCourse.selection(greenNorth: 150, features: [fairway, water]), greenNorth: 150,
                              clubs: clubs(irons))

        XCTAssertGreaterThan(advice.aimOffset, 0)
    }

    func testWaterShortOfTheGreenThatCantBeClearedLaysUp() throws {
        // A 50 m wide band of water from 150 to 200 m, with the green at 230 m. The 3 wood's
        // average lands in it and no club carries it.
        let water: (FeatureType, [Coordinate]) = (.water, PlayCourse.rectangle(north: 150...200, east: -100...100))
        let advice = try best(PlayCourse.selection(greenNorth: 230, features: [(.fairway, PlayCourse.rectangle(north: 20...145, east: -20...20)), water]),
                              greenNorth: 230, clubs: clubs(irons))

        XCTAssertLessThan(Double(advice.yards) * 0.9144, 150, "\(advice.club.name) should stop short of the water")
    }

    func testTheExpectedScoreCountsTheShot() throws {
        // A 50-yard pitch can't hole out in less than 2
        let advice = try best(PlayCourse.selection(greenNorth: 46), greenNorth: 46, clubs: clubs([("lw", 50)]))

        XCTAssertGreaterThan(advice.expectedStrokes, 2)
        XCTAssertLessThan(advice.expectedStrokes, 3)
    }

    // MARK: - For the player

    private let longHole = PlayCourse.selection(greenNorth: 400)
    private let woods = [("dr", 230), ("3w", 215), ("5i", 165), ("pu", 0)]

    private func round(_ selection: CourseSelection, status: RoundStatus = .active) -> Round {
        Round(status: status, courseSelection: selection)
    }

    private func request(_ round: Round, holeIndex: Int = 0, at north: Double = 0,
                         clubs: [(club: Club, distance: ClubDistance)]? = nil) -> ClubAdvice.Request? {
        ClubAdvice.request(at: PlayCourse.point(north: north), round: round, holeIndex: holeIndex,
                           distances: clubs ?? self.clubs(woods), missAngle: 6.4, greenZone: 10)
    }

    private func advice(_ round: Round, at north: Double = 0) async throws -> ClubAdvice {
        let request = try XCTUnwrap(request(round, at: north))
        let advice = await ClubAdviser().advice(for: request)
        return try XCTUnwrap(advice)
    }

    func testTheDriverIsOnlyForATeeShot() async throws {
        let round = round(longHole)
        let teeShot = try await advice(round)
        XCTAssertEqual(teeShot.club.id, "dr", "Nothing goes farther off the tee")

        round.holes[0].strokes = [Stroke(coordinate: PlayCourse.point(north: 0))]
        let second = try await advice(round)
        XCTAssertEqual(second.club.id, "3w")
    }

    func testThePutterIsNeverPicked() throws {
        let request = try XCTUnwrap(request(round(longHole)))

        XCTAssertFalse(request.clubs.contains { $0.club.kind == .putter })
        XCTAssertNil(self.request(round(longHole), clubs: clubs([("pu", 30)])), "No club to hit")
    }

    func testNoAdviceOnTheGreenOrInTheGreenZone() {
        // The green's edge is at 385 m, and the Green Zone is 10 m
        XCTAssertNil(request(round(longHole), at: 400), "On the green")
        XCTAssertNil(request(round(longHole), at: 378), "In the Green Zone")
        XCTAssertNotNil(request(round(longHole), at: 370), "Past the Green Zone")
    }

    func testNoAdviceOutsideAnActiveRoundOrOffTheDisplayHole() {
        XCTAssertNil(request(round(longHole, status: .ended)))
        XCTAssertNil(request(round(longHole), holeIndex: 1), "Hole 2 is not the display hole")
    }

    func testTheAimPointIsTheClubsAverageAlongTheAim() async throws {
        let advice = try await advice(round(longHole))
        let start = PlayCourse.point(north: 0)

        XCTAssertEqual(advice.startCoordinate.latitude, start.latitude, accuracy: 1e-9)
        XCTAssertEqual(LocalDistance.meters(fromLat: start.latitude, lon: start.longitude,
                                            toLat: advice.aimCoordinate.latitude, lon: advice.aimCoordinate.longitude),
                       230 * 0.9144, accuracy: 0.01)
        XCTAssertEqual(advice.corners(k: 2).count, 4)
    }

    // MARK: - The player's own aim

    func testADraggedAimTakesTheClubNearestTheYards() throws {
        let start = PlayCourse.point(north: 0)
        // 150 yards north: the 7 iron's 145 is nearest
        let shot = try XCTUnwrap(CaddieShot.aimed(at: PlayCourse.point(north: 150 * 0.9144), from: start,
                                                  clubs: clubs(irons), missAngle: 6.4))

        XCTAssertEqual(shot.club.id, "7i")
        XCTAssertEqual(shot.yards, 145)
        XCTAssertEqual(shot.aimCoordinate.longitude, start.longitude, accuracy: 1e-9, "Straight at the point")
        XCTAssertEqual(LocalDistance.meters(fromLat: start.latitude, lon: start.longitude,
                                            toLat: shot.aimCoordinate.latitude, lon: shot.aimCoordinate.longitude),
                       145 * 0.9144, accuracy: 0.01, "At the club's average")
    }

    func testADraggedAimNeedsAClub() {
        XCTAssertNil(CaddieShot.aimed(at: PlayCourse.point(north: 100), from: PlayCourse.point(north: 0), clubs: [],
                                      missAngle: 6.4))
    }

    func testTheClubsToHitLeaveOutThePutterAndTheDriverAfterTheTee() {
        let all = clubs(woods)

        XCTAssertEqual(ClubAdvice.clubs(from: all, isTeeShot: true).map(\.club.id), ["dr", "3w", "5i"])
        XCTAssertEqual(ClubAdvice.clubs(from: all, isTeeShot: false).map(\.club.id), ["3w", "5i"])
    }

    // MARK: - When it is worked out

    private func inputs(_ round: Round, missAngle: Double = 6.4) -> ClubAdviceState.Inputs {
        ClubAdviceState.Inputs(round: round, holeIndex: 0, distances: clubs(woods), missAngle: missAngle, greenZone: 10)
    }

    func testItIsWorkedOutAgainWhenThePlayerMoves3Yards() {
        let round = round(longHole)
        var state = ClubAdviceState()

        XCTAssertNotNil(state.update(inputs(round), round: round, location: PlayCourse.point(north: 0)))
        XCTAssertNil(state.update(inputs(round), round: round, location: PlayCourse.point(north: 2.5)),
                     "2.5 m is under 3 yards")
        XCTAssertNotNil(state.update(inputs(round), round: round, location: PlayCourse.point(north: 3)))
    }

    func testItIsWorkedOutAgainWhenWhatItComesFromChanges() throws {
        let round = round(longHole)
        var state = ClubAdviceState()
        _ = state.update(inputs(round), round: round, location: PlayCourse.point(north: 0))

        XCTAssertNotNil(state.update(inputs(round, missAngle: 7), round: round, location: PlayCourse.point(north: 0)))

        round.holes[0].strokes = [Stroke(coordinate: PlayCourse.point(north: 0))]
        let request = try XCTUnwrap(state.update(inputs(round, missAngle: 7), round: round,
                                                 location: PlayCourse.point(north: 0)), "A stroke takes the driver away")
        XCTAssertFalse(request.clubs.contains { $0.club.id == "dr" })
    }

    func testOnlyTheNewestAnswerShows() async throws {
        let round = round(longHole)
        var state = ClubAdviceState()
        let older = try XCTUnwrap(state.update(inputs(round), round: round, location: PlayCourse.point(north: 0)))
        let newer = try XCTUnwrap(state.update(inputs(round), round: round, location: PlayCourse.point(north: 20)))
        let adviser = ClubAdviser()

        state.finish(await adviser.advice(for: older), generation: older.generation)
        XCTAssertNil(state.advice, "An answer to an older request is dropped")
        state.finish(await adviser.advice(for: newer), generation: newer.generation)
        XCTAssertNotNil(state.advice)
    }

    func testNoAdviceToShowClearsIt() async throws {
        let round = round(longHole)
        var state = ClubAdviceState()
        let request = try XCTUnwrap(state.update(inputs(round), round: round, location: PlayCourse.point(north: 0)))
        state.finish(await ClubAdviser().advice(for: request), generation: request.generation)
        XCTAssertNotNil(state.advice)

        XCTAssertNil(state.update(inputs(round), round: round, location: PlayCourse.point(north: 400)), "On the green")
        XCTAssertNil(state.advice)
        XCTAssertNil(state.update(inputs(round), round: round, location: nil))
        XCTAssertNil(state.advice)
    }
}

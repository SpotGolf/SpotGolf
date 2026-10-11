import CoreLocation
import XCTest
@testable import SpotGolf

final class ClubGuessTests: XCTestCase {

    private let bag = GolfBag.standard

    private func guess(_ yards: Int?, onGreen: Bool = false, teeShot: Bool = false, in bag: GolfBag? = nil) -> String? {
        ClubGuess.club(in: bag ?? self.bag, yardsToTarget: yards, isOnGreen: onGreen, isTeeShot: teeShot)?.id
    }

    func testPutterOnTheGreen() {
        XCTAssertEqual(guess(5, onGreen: true), "pu")
        XCTAssertEqual(guess(5, onGreen: true, in: GolfBag(ids: ["dr", "lw"])), "lw", "Without a putter, the nearest club")
    }

    func testDriverOffTheTeeAndTheLongestWoodAfter() {
        XCTAssertEqual(guess(400, teeShot: true), "dr")
        XCTAssertEqual(guess(400), "3w")
        XCTAssertEqual(guess(225, teeShot: true), "dr", "230 is nearer 225 than 215")
        XCTAssertEqual(guess(225), "3w")
    }

    func testNearestClubByYardsWithTiesToTheLongerClub() {
        XCTAssertEqual(guess(146), "7i")
        XCTAssertEqual(guess(150), "6i", "145 and 155 tie: the 6 iron is longer")
        XCTAssertEqual(guess(102), "sw", "90 is nearer than 115")
    }

    func testChipGetsTheShortestWedge() {
        XCTAssertEqual(guess(20), "lw")
        XCTAssertEqual(guess(0), "lw")
    }

    func testWithoutYardsOnlyATeeShotIsGuessed() {
        XCTAssertEqual(guess(nil, teeShot: true), "dr")
        XCTAssertNil(guess(nil))
    }

    func testEmptyBagGuessesNothing() {
        XCTAssertNil(guess(150, in: GolfBag(ids: [])))
        XCTAssertNil(guess(150, in: GolfBag(ids: ["pu"])), "The putter has no distance")
        XCTAssertEqual(guess(5, onGreen: true, in: GolfBag(ids: ["pu"])), "pu")
    }

    func testGuessFromTheCourse() {
        let round = Round(date: Date(), courseSelection: PathCourse.selection)
        let tee = PathCourse.coordinate(north: 0, east: 0).clLocation.coordinate
        let approach = PathCourse.coordinate(north: 280, east: 0).clLocation.coordinate
        let green = PathCourse.coordinate(north: 300, east: 0).clLocation.coordinate

        XCTAssertEqual(HoleOverview.guessedClub(round, holeIndex: 0, strokeIndex: 0, at: tee, bag: bag)?.id, "dr")
        XCTAssertEqual(HoleOverview.guessedClub(round, holeIndex: 0, strokeIndex: 1, at: approach, bag: bag)?.id, "lw",
                       "20 m from the green's center is a chip")
        XCTAssertEqual(HoleOverview.guessedClub(round, holeIndex: 0, strokeIndex: 2, at: green, bag: bag)?.id, "pu")
    }

}

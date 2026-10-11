import XCTest
@testable import SpotGolf

final class GolfBagTests: XCTestCase {

    func testEveryClubHasItsOwnID() {
        let ids = Club.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(Club.named("7i")?.shortName, "7i")
        XCTAssertEqual(Club.named("52")?.shortName, "52°")
        XCTAssertNil(Club.named("10i"))
    }

    func testEveryClubButThePutterHasADefaultDistance() {
        for club in Club.all {
            if club.kind == .putter {
                XCTAssertNil(club.defaultDistance, "The putter has no distance")
            } else {
                XCTAssertNotNil(club.defaultDistance, "\(club.name) should have a default distance")
            }
        }
        XCTAssertEqual(Club.named("dr")?.defaultDistance, 230)
        XCTAssertEqual(Club.named("7i")?.defaultDistance, 145)
        XCTAssertEqual(Club.named("64")?.defaultDistance, 55)
    }

    func testStandardBagIsTheFourteenStandardClubsAtTheirDefaults() {
        let bag = GolfBag.standard

        XCTAssertEqual(bag.clubs.map(\.shortName), ["Dr", "3w", "5w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "PW", "SW", "LW", "Pu"])
        XCTAssertTrue(bag.isFull)
        XCTAssertEqual(bag.distance(of: Club.named("3w")!), 215)
        XCTAssertNil(bag.distance(of: Club.named("pu")!))
        XCTAssertNil(bag.distance(of: Club.named("2w")!), "A club not in the bag has no distance")
    }

    func testBagKeepsBagOrderOneOfEachClubAndGivenDistances() {
        let driver = Club.named("dr")!
        let putter = Club.named("pu")!

        let bag = GolfBag(clubs: [putter, driver, driver], distances: [driver: 250])

        XCTAssertEqual(bag.clubs, [driver, putter])
        XCTAssertEqual(bag.distance(of: driver), 250)
        XCTAssertFalse(bag.isFull)
    }

    func testUnknownIDsAreDropped() {
        XCTAssertEqual(GolfBag(ids: ["pu", "bogus", "dr"]).clubs.map(\.id), ["dr", "pu"])
        XCTAssertEqual(GolfBag(ids: []).clubs, [])
    }

}

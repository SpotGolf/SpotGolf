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

    func testStandardBagIsTheFourteenStandardClubs() {
        let bag = GolfBag.standard

        XCTAssertEqual(bag.clubs.map(\.shortName), ["Dr", "3w", "5w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "PW", "SW", "LW", "Pu"])
        XCTAssertTrue(bag.isFull)
    }

    func testRawValueRoundTripsAndDropsUnknownClubs() {
        XCTAssertEqual(GolfBag(rawValue: GolfBag.standard.rawValue), GolfBag.standard)
        XCTAssertEqual(GolfBag.standard.rawValue, "dr,3w,5w,3i,4i,5i,6i,7i,8i,9i,pw,sw,lw,pu")

        let bag = GolfBag(rawValue: "pu,bogus,dr,dr")

        XCTAssertEqual(bag?.clubs.map(\.id), ["dr", "pu"], "The bag keeps bag order and one of each club")
    }

    func testEmptyRawValueIsAnEmptyBag() {
        XCTAssertEqual(GolfBag(rawValue: "")?.clubs, [])
    }

    func testTogglingRemovesAndAddsAClubInBagOrder() {
        var bag = GolfBag.standard
        let fiveWood = Club.named("5w")!
        let fourHybrid = Club.named("4h")!

        bag.toggle(fiveWood)
        XCTAssertFalse(bag.contains(fiveWood))
        XCTAssertEqual(bag.clubs.count, 13)

        bag.toggle(fourHybrid)
        XCTAssertEqual(bag.clubs.map(\.id).prefix(3), ["dr", "3w", "4h"])
        XCTAssertTrue(bag.isFull)
    }

    func testAFullBagTakesNoMoreClubs() {
        var bag = GolfBag.standard

        bag.toggle(Club.named("2w")!)

        XCTAssertEqual(bag, GolfBag.standard)
    }

}
